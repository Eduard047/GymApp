package com.example.gymapp.push

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import com.example.gymapp.BuildConfig
import com.example.gymapp.MainActivity
import com.example.gymapp.R
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.CloudAuthManager
import com.google.android.gms.tasks.Task
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal data class PushUiState(
    val configured: Boolean = false,
    val isCloudAccount: Boolean = false,
    val enabled: Boolean = false,
    val permissionGranted: Boolean = false,
    val channelEnabled: Boolean = false,
    val registered: Boolean = false,
    val isSyncing: Boolean = false,
    val hasError: Boolean = false
)

internal class AndroidPushManager(
    private val context: Context,
    private val authManager: CloudAuthManager,
    private val navigationInbox: PushNavigationInbox
) {
    private val applicationContext = context.applicationContext
    private val store = PushInstallationStore(applicationContext)
    private val workScheduler = PushWorkScheduler(applicationContext)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val operationMutex = Mutex()
    private val notificationStateGate = PushNotificationStateGate()
    private val operationEpoch = AtomicLong(0L)
    private val initialized = AtomicBoolean(false)
    private val deliveryArmed = AtomicBoolean(false)
    private val _uiState = MutableStateFlow(PushUiState(configured = BuildConfig.FIREBASE_CONFIGURED))
    val uiState: StateFlow<PushUiState> = _uiState.asStateFlow()

    @Volatile
    private var messaging: FirebaseMessaging? = null

    @Volatile
    private var latestProviderToken: String? = null

    @Volatile
    private var lastObservedCloudSession: AccountSession.Cloud? = null

    fun initialize() {
        if (!initialized.compareAndSet(false, true)) return
        authManager.setPushInstallationForLogout(::prepareForCloudLogout)
        if (BuildConfig.FIREBASE_CONFIGURED) {
            createNotificationChannel()
            messaging = initializeFirebaseMessaging()
            messaging?.isAutoInitEnabled = store.isEnabled()
        }
        restoreDeliveryArmFromDurableState()
        // The first StateFlow emission restores this same generation; it is not an account
        // switch and must not cancel valid notifications that cold-started the process.
        lastObservedCloudSession = authManager.authState.value.session as? AccountSession.Cloud
        scope.launch {
            authManager.authState.collect { authState ->
                handleAccountTransition(authState.session)
            }
        }
        refreshSystemState()
    }

    private fun restoreDeliveryArmFromDurableState() {
        notificationStateGate.runExclusive {
            val session = authManager.authState.value.session
            val installationId = store.existingInstallationIdOrNull()
            val binding = store.binding()
            deliveryArmed.set(
                canRestorePushDeliveryArm(
                    session = session,
                    binding = binding,
                    installationId = installationId,
                    pendingRevocation = store.pendingRevocation(),
                    configured = BuildConfig.FIREBASE_CONFIGURED,
                    enabled = store.isEnabled(),
                    permissionGranted = notificationPermissionGranted(),
                    channelEnabled = notificationChannelEnabled()
                )
            )
        }
    }

    fun enable() {
        if (!BuildConfig.FIREBASE_CONFIGURED || !notificationPermissionGranted()) {
            refreshUiState()
            return
        }
        createNotificationChannel()
        if (!notificationChannelEnabled()) {
            refreshUiState()
            return
        }
        if (!store.setEnabled(true)) {
            _uiState.value = currentUiState(hasError = true)
            return
        }
        messaging?.isAutoInitEnabled = true
        operationEpoch.incrementAndGet()
        refreshUiState(isSyncing = true)
        workScheduler.enqueue(replace = true)
        scope.launch { synchronizeRegistration(force = true) }
    }

    fun disable() {
        val session = authManager.authState.value.session as? AccountSession.Cloud
        val preferenceSaved = store.setEnabled(false)
        val pending = preparePendingRevocation(session, deleteProviderToken = true)
        val invalidation = invalidateDelivery(
            clearBinding = canClearPushBindingAfterRevocationPreparation(
                pending.marker,
                pending.saved
            )
        )
        messaging?.isAutoInitEnabled = false
        refreshUiState(
            hasError = !preferenceSaved || !pending.saved || !invalidation.bindingCleared
        )
        scope.launch {
            executeRevocation(
                session,
                pending.marker,
                pendingMarkerSaved = pending.saved,
                deleteProviderToken = true
            )
        }
        workScheduler.enqueue(replace = true)
    }

    fun refreshSystemState() {
        if (BuildConfig.FIREBASE_CONFIGURED) createNotificationChannel()
        refreshUiState()
        val session = authManager.authState.value.session as? AccountSession.Cloud
        val pending = store.pendingRevocation()
        val enabled = store.isEnabled()
        val hasStoredBinding = store.binding() != null
        when {
            pending != null && session?.userId == pending.userId -> {
                // Re-commit even an in-memory marker before letting any later
                // clear depend on it. SharedPreferences may expose values from
                // a commit that returned false even though they are not durable.
                val prepared = preparePendingRevocation(
                    session,
                    deleteProviderToken = pending.deleteProviderToken
                )
                val invalidation = invalidateDelivery(
                    clearBinding = canClearPushBindingAfterRevocationPreparation(
                        prepared.marker,
                        prepared.saved
                    )
                )
                refreshUiState(hasError = !invalidation.bindingCleared)
                scope.launch {
                    executeRevocation(
                        session,
                        prepared.marker,
                        pendingMarkerSaved = prepared.saved,
                        deleteProviderToken = prepared.marker?.deleteProviderToken == true
                    )
                    if (canRegisterNow(
                            authManager.authState.value.session as? AccountSession.Cloud
                        )
                    ) {
                        synchronizeRegistration(force = true)
                    }
                }
            }
            !enabled && pending == null && hasStoredBinding -> {
                val prepared = preparePendingRevocation(
                    session,
                    deleteProviderToken = true
                )
                val invalidation = invalidateDelivery(
                    clearBinding = canClearPushBindingAfterRevocationPreparation(
                        prepared.marker,
                        prepared.saved
                    )
                )
                refreshUiState(
                    hasError = !prepared.saved || !invalidation.bindingCleared
                )
                scope.launch {
                    executeRevocation(
                        session,
                        prepared.marker,
                        pendingMarkerSaved = prepared.saved,
                        deleteProviderToken = true
                    )
                }
            }
            enabled && !canRegisterNow(session) -> {
                val prepared = preparePendingRevocation(
                    session,
                    deleteProviderToken = false
                )
                val invalidation = invalidateDelivery(
                    clearBinding = canClearPushBindingAfterRevocationPreparation(
                        prepared.marker,
                        prepared.saved
                    )
                )
                refreshUiState(
                    hasError = !prepared.saved || !invalidation.bindingCleared
                )
                scope.launch {
                    executeRevocation(
                        session,
                        prepared.marker,
                        pendingMarkerSaved = prepared.saved,
                        deleteProviderToken = false
                    )
                }
            }
            enabled && session != null -> {
                scope.launch { synchronizeRegistration(force = false) }
            }
        }
        if (enabled || pending != null || hasStoredBinding) {
            workScheduler.enqueue(replace = false)
        }
    }

    internal suspend fun reconcileFromWorker(): Boolean {
        var session = authManager.authState.value.session as? AccountSession.Cloud
        val pending = store.pendingRevocation()
        if (pending != null && session?.userId == pending.userId) {
            val prepared = preparePendingRevocation(
                session,
                deleteProviderToken = pending.deleteProviderToken
            )
            if (!executeRevocation(
                    session,
                    prepared.marker,
                    pendingMarkerSaved = prepared.saved,
                    deleteProviderToken = prepared.marker?.deleteProviderToken == true
                )
            ) {
                return false
            }
            session = authManager.authState.value.session as? AccountSession.Cloud
        }

        if (!store.isEnabled()) return true
        if (!BuildConfig.FIREBASE_CONFIGURED) return true
        if (!canRegisterNow(session)) {
            if (session == null) return true
            val prepared = preparePendingRevocation(
                session,
                deleteProviderToken = false
            )
            val invalidation = invalidateDelivery(
                clearBinding = canClearPushBindingAfterRevocationPreparation(
                    prepared.marker,
                    prepared.saved
                )
            )
            if (!prepared.saved || !invalidation.bindingCleared) return false
            return executeRevocation(
                session,
                prepared.marker,
                pendingMarkerSaved = prepared.saved,
                deleteProviderToken = false
            )
        }
        return synchronizeRegistration(force = pending != null)
    }

    fun onNewProviderToken(providerToken: String) {
        if (!isValidFcmProviderToken(providerToken)) {
            latestProviderToken = null
            invalidateDelivery(clearBinding = true, preserveDeliveryState = true)
            refreshUiState(hasError = true)
            return
        }
        val tokenChanged = latestProviderToken != providerToken
        latestProviderToken = providerToken
        if (tokenChanged) {
            invalidateDelivery(clearBinding = true, preserveDeliveryState = true)
        }
        if (BuildConfig.FIREBASE_CONFIGURED && store.isEnabled()) {
            val scheduled = workScheduler.enqueue(
                replace = tokenChanged,
                awaitPersistence = true
            )
            if (!scheduled) refreshUiState(hasError = true)
            scope.launch { synchronizeRegistration(force = tokenChanged) }
        }
    }

    fun handleIncomingData(
        data: Map<String, String>,
        hasNotificationPayload: Boolean
    ) {
        val payload = parsePushPayload(data, hasNotificationPayload) ?: return
        if (!isPayloadBoundToCurrentSession(payload)) return
        showNotification(payload)
    }

    fun consumeNotificationTap(intent: Intent): AccountBoundPushNavigation? {
        val payload = runCatching { parseNotificationTapIntent(intent) }.getOrNull()
        intent.action = null
        intent.replaceExtras(null)
        val binding = payload?.let(::currentBindingForPayload) ?: return null
        if (!store.isCurrentDisplayedPayload(
                payload,
                binding.session,
                binding.installationId
            )
        ) {
            return null
        }
        cancelPushNotification(payload)
        return AccountBoundPushNavigation(
            payload = payload,
            userId = binding.session.userId,
            sessionGeneration = binding.session.sessionGeneration,
            installationId = binding.installationId
        )
    }

    fun isNavigationBoundToCurrentSession(navigation: AccountBoundPushNavigation): Boolean {
        if (!navigation.matchesSession(authManager.authState.value.session)) return false
        val payloadBinding = currentStoredBinding(navigation.bindingId) ?: return false
        return payloadBinding.session.userId == navigation.userId &&
            payloadBinding.session.sessionGeneration == navigation.sessionGeneration &&
            payloadBinding.installationId == navigation.installationId &&
            store.isCurrentDisplayedPayload(
                navigation.payload,
                payloadBinding.session,
                payloadBinding.installationId
            )
    }

    fun openNotificationSettings() {
        val channelIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, applicationContext.packageName)
                putExtra(Settings.EXTRA_CHANNEL_ID, PUSH_CHANNEL_ID)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                "package:${applicationContext.packageName}".toUri()
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }
        runCatching { applicationContext.startActivity(channelIntent) }
    }

    private suspend fun handleAccountTransition(session: AccountSession?) {
        val cloudSession = session as? AccountSession.Cloud
        val previous = lastObservedCloudSession
        lastObservedCloudSession = cloudSession
        val generationChanged = previous?.userId != cloudSession?.userId ||
            previous?.sessionGeneration != cloudSession?.sessionGeneration
        var transitionError = false
        if (generationChanged) {
            val binding = store.binding()
            var prepared = PreparedPushRevocation(marker = null, saved = true)
            if (previous != null && binding?.matches(
                    previous,
                    binding.installationId,
                    binding.bindingId
            ) == true
            ) {
                prepared = preparePendingRevocation(
                    previous,
                    deleteProviderToken = false
                )
                transitionError = !prepared.saved
            }
            val bindingBelongsToCurrentGeneration = binding != null &&
                cloudSession != null &&
                binding.userId == cloudSession.userId &&
                binding.sessionGeneration == cloudSession.sessionGeneration
            val invalidation = invalidateDelivery(
                clearBinding = !bindingBelongsToCurrentGeneration &&
                    canClearPushBindingAfterRevocationPreparation(
                        prepared.marker,
                        prepared.saved
                    )
            )
            transitionError = transitionError || !invalidation.bindingCleared
            workScheduler.enqueue(replace = true)
        }
        refreshUiState(hasError = transitionError)
        if (cloudSession != null && canRegisterNow(cloudSession)) {
            synchronizeRegistration(force = false)
        }
    }

    private suspend fun synchronizeRegistration(force: Boolean): Boolean {
        if (!BuildConfig.FIREBASE_CONFIGURED) return true
        return operationMutex.withLock {
            val session = authManager.authState.value.session as? AccountSession.Cloud
            if (!canRegisterNow(session)) {
                refreshUiState()
                return@withLock true
            }
            checkNotNull(session)
            val firebaseMessaging = messaging ?: run {
                refreshUiState(hasError = true)
                return@withLock false
            }
            val installationId = runCatching { store.installationId() }.getOrElse {
                refreshUiState(hasError = true)
                return@withLock false
            }
            var pendingBeforeRegistration = store.pendingRevocation()
            val currentBinding = store.binding()
            var priorOwnerCleanupPersisted = true
            val hasForeignOwnerState = currentBinding?.userId?.let { it != session.userId } == true ||
                pendingBeforeRegistration?.userId?.let { it != session.userId } == true
            if (hasForeignOwnerState) {
                val prepared = preparePendingRevocation(
                    session,
                    deleteProviderToken = pendingBeforeRegistration?.deleteProviderToken == true
                )
                pendingBeforeRegistration = prepared.marker
                priorOwnerCleanupPersisted = prepared.saved
            }
            if (!canBeginPushRegistration(
                    session = session,
                    binding = currentBinding,
                    pendingRevocation = pendingBeforeRegistration,
                    pendingMarkerSaved = priorOwnerCleanupPersisted
                )
            ) {
                // The foreign binding is the only restart-safe source for the
                // previous owner. Never clear it or contact registration for a
                // replacement account until its cleanup is durable.
                refreshUiState(hasError = true)
                return@withLock false
            }
            @Suppress("DEPRECATION")
            val fetchedToken = latestProviderToken ?: runCatching {
                // The current server contract addresses FCM registration tokens. FCM 25.1's
                // replacement API addresses Firebase installation IDs and cannot be substituted
                // until the provider contract is migrated end to end.
                firebaseMessaging.token.awaitResult()
            }.getOrElse {
                refreshUiState(hasError = true)
                return@withLock false
            }
            val providerToken = latestProviderToken ?: fetchedToken.also {
                latestProviderToken = it
            }
            if (!isValidFcmProviderToken(providerToken)) {
                latestProviderToken = null
                invalidateDelivery(clearBinding = true, preserveDeliveryState = true)
                refreshUiState(hasError = true)
                return@withLock false
            }
            val tokenDigest = providerTokenDigest(providerToken)
            val bindingStillFresh = pendingBeforeRegistration == null &&
                currentBinding != null &&
                currentBinding.matches(session, installationId, currentBinding.bindingId) &&
                currentBinding.providerTokenDigest == tokenDigest &&
                System.currentTimeMillis() - currentBinding.registeredAtMillis in
                    0..MAX_REGISTRATION_REFRESH_AGE_MILLIS
            if (!force && bindingStillFresh) {
                val armed = armCurrentBinding(
                    session = session,
                    installationId = installationId,
                    bindingId = currentBinding.bindingId,
                    providerToken = providerToken,
                    expectedEpoch = operationEpoch.get()
                )
                refreshUiState(hasError = !armed)
                return@withLock armed
            }

            val invalidation = invalidateDelivery(
                clearBinding = true,
                preserveDeliveryState = true
            )
            val attempt = PushRegistrationAttempt(
                installationId = installationId,
                userId = session.userId,
                sessionGeneration = session.sessionGeneration,
                providerToken = providerToken,
                epoch = invalidation.epoch
            )
            // A stale binding must never authorize messages while the server address changes.
            refreshUiState(
                isSyncing = true,
                hasError = !invalidation.bindingCleared
            )
            val registration = runCatching {
                authManager.registerPushInstallation(
                    session = session,
                    installationId = installationId,
                    providerToken = providerToken,
                    locale = currentLocale(),
                    appVersion = BuildConfig.VERSION_NAME
                )
            }.getOrElse {
                refreshUiState(hasError = true)
                return@withLock false
            }
            val commitAllowed = canCommitPushRegistration(
                attempt = attempt,
                activeSession = authManager.authState.value.session,
                currentInstallationId = store.existingInstallationIdOrNull().orEmpty(),
                currentProviderToken = latestProviderToken,
                currentEpoch = operationEpoch.get(),
                enabled = canRegisterNow(
                    authManager.authState.value.session as? AccountSession.Cloud
                )
            )
            if (!commitAllowed) {
                refreshUiState()
                return@withLock true
            }
            val savedBinding = PushInstallationBinding(
                installationId = registration.installationId,
                userId = attempt.userId,
                sessionGeneration = attempt.sessionGeneration,
                bindingId = registration.bindingId,
                registrationRevision = registration.registrationRevision,
                providerTokenDigest = tokenDigest,
                registeredAtMillis = System.currentTimeMillis()
            )
            val saved = store.saveBinding(savedBinding)
            val pendingCleared = saved && store.clearPendingRevocationSupersededBy(
                replacement = savedBinding,
                expectedPending = pendingBeforeRegistration
            )
            val armed = saved && pendingCleared && armCurrentBinding(
                session = session,
                installationId = installationId,
                bindingId = savedBinding.bindingId,
                providerToken = providerToken,
                expectedEpoch = attempt.epoch
            )
            refreshUiState(hasError = !armed)
            armed
        }
    }

    private suspend fun executeRevocation(
        session: AccountSession.Cloud?,
        pending: PushPendingRevocation?,
        pendingMarkerSaved: Boolean,
        deleteProviderToken: Boolean
    ): Boolean = operationMutex.withLock {
            val clearBindingBeforeRevocation =
                canClearPushBindingAfterRevocationPreparation(pending, pendingMarkerSaved)
            val invalidation = invalidateDelivery(clearBinding = clearBindingBeforeRevocation)
            val revocationConfirmed = if (session != null && pending != null) {
                val response = runCatching {
                    authManager.revokePushInstallation(session, pending.installationId)
                }.getOrNull()
                // A parsed `revoked=false` means this owner row was already inactive, which is
                // the same idempotent desired state. Transport/parser/auth failures stay null.
                pushRevocationReachedDesiredState(response)
            } else {
                pending == null
            }
            val markerCleared = if (revocationConfirmed && pending != null) {
                store.clearPendingRevocation(pending.installationId)
            } else {
                pending == null
            }
            if (deleteProviderToken) {
                latestProviderToken = null
                messaging?.let { firebaseMessaging ->
                    @Suppress("DEPRECATION")
                    runCatching { firebaseMessaging.deleteToken().awaitResult() }
                }
            }
            val bindingCleared = if (clearBindingBeforeRevocation) {
                invalidation.bindingCleared
            } else if (revocationConfirmed && markerCleared) {
                invalidateDelivery(clearBinding = true).bindingCleared
            } else {
                false
            }
            val success = bindingCleared && revocationConfirmed && markerCleared
            refreshUiState(hasError = !success)
            success
    }

    private fun prepareForCloudLogout(session: AccountSession.Cloud): String? {
        val installationId = store.existingInstallationIdOrNull()
        val pending = preparePendingRevocation(session, deleteProviderToken = false)
        val invalidation = invalidateDelivery(
            clearBinding = canClearPushBindingAfterRevocationPreparation(
                pending.marker,
                pending.saved
            )
        )
        refreshUiState(hasError = !pending.saved || !invalidation.bindingCleared)
        // Revocation is idempotent. Returning an existing ID even after a just-completed
        // disable lets logout order its final server revoke after every in-flight RPC.
        return installationId
    }

    private fun preparePendingRevocation(
        session: AccountSession.Cloud?,
        deleteProviderToken: Boolean
    ): PreparedPushRevocation {
        val installationId = store.existingInstallationIdOrNull()
            ?: return PreparedPushRevocation(marker = null, saved = true)
        val existing = store.pendingRevocation()
        val persistedBinding = store.binding()
        val marker = resolvePushPendingRevocation(
            installationId = installationId,
            existing = existing,
            persistedBinding = persistedBinding,
            session = session,
            deleteProviderToken = deleteProviderToken
        )
            ?: return PreparedPushRevocation(marker = null, saved = true)
        // Always re-commit an existing value. SharedPreferences updates its
        // in-memory map before disk I/O, so a prior commit(false) can otherwise
        // look indistinguishable from a durable marker inside this process.
        return PreparedPushRevocation(marker, store.savePendingRevocation(marker))
    }

    private fun invalidateDelivery(
        clearBinding: Boolean,
        preserveDeliveryState: Boolean = false
    ): DeliveryInvalidation =
        notificationStateGate.runExclusive {
            val epoch = operationEpoch.incrementAndGet()
            deliveryArmed.set(false)
            navigationInbox.clear()
            val bindingCleared = !clearBinding || store.clearBinding(preserveDeliveryState)
            cancelPushNotificationsLocked()
            DeliveryInvalidation(epoch, bindingCleared)
        }

    private fun armCurrentBinding(
        session: AccountSession.Cloud,
        installationId: String,
        bindingId: String,
        providerToken: String,
        expectedEpoch: Long
    ): Boolean = notificationStateGate.runExclusive {
        val activeSession = authManager.authState.value.session as? AccountSession.Cloud
            ?: return@runExclusive false
        if (operationEpoch.get() != expectedEpoch ||
            latestProviderToken != providerToken ||
            activeSession.userId != session.userId ||
            activeSession.sessionGeneration != session.sessionGeneration ||
            !canRegisterNow(activeSession)
        ) {
            return@runExclusive false
        }
        val binding = store.binding() ?: return@runExclusive false
        if (!binding.matches(activeSession, installationId, bindingId) ||
            binding.providerTokenDigest != providerTokenDigest(providerToken)
        ) {
            return@runExclusive false
        }
        deliveryArmed.set(true)
        true
    }

    private fun isPayloadBoundToCurrentSession(payload: PushPayload): Boolean {
        return currentBindingForPayload(payload) != null
    }

    private fun currentBindingForPayload(payload: PushPayload): CurrentPushBinding? =
        currentStoredBinding(payload.bindingId)

    private fun currentStoredBinding(bindingId: String): CurrentPushBinding? {
        if (!deliveryArmed.get() ||
            !BuildConfig.FIREBASE_CONFIGURED ||
            !store.isEnabled()
        ) {
            return null
        }
        if (!notificationPermissionGranted() || !notificationChannelEnabled()) return null
        val session = authManager.authState.value.session as? AccountSession.Cloud ?: return null
        val installationId = store.existingInstallationIdOrNull() ?: return null
        val binding = store.binding() ?: return null
        return CurrentPushBinding(session, installationId)
            .takeIf { binding.matches(session, installationId, bindingId) }
    }

    private fun canRegisterNow(session: AccountSession.Cloud?): Boolean =
        BuildConfig.FIREBASE_CONFIGURED &&
            session != null &&
            store.isEnabled() &&
            notificationPermissionGranted() &&
            notificationChannelEnabled()

    private fun refreshUiState(
        isSyncing: Boolean = false,
        hasError: Boolean = false
    ) {
        _uiState.value = currentUiState(isSyncing = isSyncing, hasError = hasError)
    }

    private fun currentUiState(
        isSyncing: Boolean = false,
        hasError: Boolean = false
    ): PushUiState {
        val session = authManager.authState.value.session as? AccountSession.Cloud
        val installationId = store.existingInstallationIdOrNull()
        val binding = store.binding()
        return PushUiState(
            configured = BuildConfig.FIREBASE_CONFIGURED,
            isCloudAccount = session != null,
            enabled = store.isEnabled(),
            permissionGranted = notificationPermissionGranted(),
            channelEnabled = notificationChannelEnabled(),
            registered = deliveryArmed.get() &&
                session != null && installationId != null && binding?.let {
                it.matches(session, installationId, it.bindingId)
            } == true,
            isSyncing = isSyncing,
            hasError = hasError
        )
    }

    private fun notificationPermissionGranted(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                applicationContext,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED

    private fun notificationChannelEnabled(): Boolean {
        if (!NotificationManagerCompat.from(applicationContext).areNotificationsEnabled()) {
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        val channel = applicationContext.getSystemService(NotificationManager::class.java)
            .getNotificationChannel(PUSH_CHANNEL_ID)
        return channel != null && channel.importance != NotificationManager.IMPORTANCE_NONE
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            PUSH_CHANNEL_ID,
            applicationContext.getString(R.string.push_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = applicationContext.getString(R.string.push_channel_description)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
        }
        applicationContext.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun initializeFirebaseMessaging(): FirebaseMessaging? = runCatching {
        val options = FirebaseOptions.Builder()
            .setProjectId(BuildConfig.FIREBASE_PROJECT_ID)
            .setApplicationId(BuildConfig.FIREBASE_APPLICATION_ID)
            .setApiKey(BuildConfig.FIREBASE_API_KEY)
            .setGcmSenderId(BuildConfig.FIREBASE_SENDER_ID)
            .build()
        runCatching { FirebaseApp.getInstance() }.getOrElse {
            checkNotNull(FirebaseApp.initializeApp(applicationContext, options))
        }
        FirebaseMessaging.getInstance()
    }.getOrNull()

    private fun currentLocale(): String? {
        val locale = applicationContext.resources.configuration.locales[0]
        return normalizedPushLocale(locale?.language, locale?.country)
    }

    private fun showNotification(payload: PushPayload) {
        if (!isPayloadBoundToCurrentSession(payload)) return
        val (title, body) = notificationCopyResources(payload)
        val notification = NotificationCompat.Builder(applicationContext, PUSH_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_gymapp)
            .setContentTitle(applicationContext.getString(title))
            .setContentText(applicationContext.getString(body))
            .setCategory(NotificationCompat.CATEGORY_SOCIAL)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setContentIntent(notificationPendingIntent(payload))
            .build()
        notificationStateGate.runExclusive {
            val binding = currentBindingForPayload(payload) ?: return@runExclusive
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(
                    applicationContext,
                    Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                return@runExclusive
            }
            if (!store.canDisplay(payload, binding.session, binding.installationId)) {
                return@runExclusive
            }
            try {
                NotificationManagerCompat.from(applicationContext).notify(
                    pushNotificationTag(payload),
                    PUSH_NOTIFICATION_ID,
                    notification
                )
            } catch (_: SecurityException) {
                // Permission may be revoked between the direct check and notify().
                refreshUiState(hasError = true)
                return@runExclusive
            } catch (_: RuntimeException) {
                refreshUiState(hasError = true)
                return@runExclusive
            }
            if (!store.commitDisplayed(payload, binding.session, binding.installationId)) {
                // A tap must never authorize navigation unless the exact displayed revision was
                // durably committed. Remove the platform notification on storage failure.
                cancelPushNotificationLocked(payload)
                refreshUiState(hasError = true)
            }
        }
    }

    private fun notificationPendingIntent(payload: PushPayload): PendingIntent {
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            action = pushTapAction(payload)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putPushPayloadExtras(this, payload)
        }
        return PendingIntent.getActivity(
            applicationContext,
            pushPendingIntentRequestCode(payload),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun cancelPushNotification(payload: PushPayload) {
        notificationStateGate.runExclusive {
            cancelPushNotificationLocked(payload)
        }
    }

    private fun cancelPushNotificationLocked(payload: PushPayload) {
        NotificationManagerCompat.from(applicationContext).cancel(
            pushNotificationTag(payload),
            PUSH_NOTIFICATION_ID
        )
    }

    private fun cancelPushNotificationsLocked() {
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        runCatching {
            manager.activeNotifications
                .filter { it.tag?.startsWith(PUSH_NOTIFICATION_TAG_PREFIX) == true }
                .forEach { manager.cancel(it.tag, it.id) }
        }
    }

    private fun notificationCopyResources(payload: PushPayload): Pair<Int, Int> = when (payload) {
        is PushPayload.Social -> when (payload.type) {
            SocialPushType.FriendRequestReceived ->
                R.string.push_friend_request_received_title to
                    R.string.push_friend_request_received_body
            SocialPushType.FriendRequestAccepted ->
                R.string.push_friend_request_accepted_title to
                    R.string.push_friend_request_accepted_body
            SocialPushType.WorkoutInviteReceived ->
                R.string.push_workout_invite_received_title to
                    R.string.push_workout_invite_received_body
            SocialPushType.WorkoutInviteAccepted ->
                R.string.push_workout_invite_accepted_title to
                    R.string.push_workout_invite_accepted_body
        }

        is PushPayload.Live -> when (payload.kind) {
            LivePushKind.Invite ->
                R.string.push_live_invite_received_title to
                    R.string.push_live_invite_received_body
            LivePushKind.Joined ->
                R.string.push_live_invite_accepted_title to
                    R.string.push_live_invite_accepted_body
            LivePushKind.Started ->
                R.string.push_live_room_started_title to R.string.push_live_room_started_body
            LivePushKind.ParticipantFinished ->
                R.string.push_live_participant_finished_title to
                    R.string.push_live_participant_finished_body
            LivePushKind.RoomClosed ->
                R.string.push_live_room_closed_title to R.string.push_live_room_closed_body
        }
    }

    private suspend fun <T> Task<T>.awaitResult(): T = suspendCancellableCoroutine { continuation ->
        addOnCompleteListener { task ->
            if (!continuation.isActive) return@addOnCompleteListener
            if (task.isSuccessful) {
                continuation.resume(task.result)
            } else {
                continuation.resumeWithException(
                    task.exception ?: IllegalStateException("Firebase operation failed.")
                )
            }
        }
    }

    private companion object {
        const val MAX_REGISTRATION_REFRESH_AGE_MILLIS = 30L * 24 * 60 * 60 * 1_000
        const val PUSH_NOTIFICATION_ID = 41_701
        const val PUSH_NOTIFICATION_TAG_PREFIX = "gymapp_push:"
    }
}

private data class CurrentPushBinding(
    val session: AccountSession.Cloud,
    val installationId: String
)

private data class DeliveryInvalidation(
    val epoch: Long,
    val bindingCleared: Boolean
)

private data class PreparedPushRevocation(
    val marker: PushPendingRevocation?,
    val saved: Boolean
)

internal fun canRestorePushDeliveryArm(
    session: AccountSession?,
    binding: PushInstallationBinding?,
    installationId: String?,
    pendingRevocation: PushPendingRevocation?,
    configured: Boolean,
    enabled: Boolean,
    permissionGranted: Boolean,
    channelEnabled: Boolean
): Boolean {
    val cloud = session as? AccountSession.Cloud ?: return false
    val storedBinding = binding ?: return false
    val currentInstallationId = installationId ?: return false
    return configured &&
        enabled &&
        permissionGranted &&
        channelEnabled &&
        pendingRevocation == null &&
        storedBinding.matches(cloud, currentInstallationId, storedBinding.bindingId)
}

internal fun resolvePushPendingRevocation(
    installationId: String,
    existing: PushPendingRevocation?,
    persistedBinding: PushInstallationBinding?,
    session: AccountSession.Cloud?,
    deleteProviderToken: Boolean
): PushPendingRevocation? {
    if (existing != null) {
        return existing.copy(
            deleteProviderToken = deleteProviderToken || existing.deleteProviderToken
        )
    }
    val ownerUserId = persistedBinding?.userId ?: session?.userId ?: return null
    val ownerGeneration = persistedBinding?.sessionGeneration
        ?: session?.sessionGeneration
        ?: return null
    return PushPendingRevocation(
        installationId = installationId,
        userId = ownerUserId,
        sessionGeneration = ownerGeneration,
        deleteProviderToken = deleteProviderToken
    )
}

internal fun canClearPushBindingAfterRevocationPreparation(
    marker: PushPendingRevocation?,
    markerSaved: Boolean
): Boolean = marker == null || markerSaved

internal fun canBeginPushRegistration(
    session: AccountSession.Cloud,
    binding: PushInstallationBinding?,
    pendingRevocation: PushPendingRevocation?,
    pendingMarkerSaved: Boolean
): Boolean {
    val foreignBinding = binding?.takeIf { it.userId != session.userId }
    val foreignPending = pendingRevocation?.takeIf { it.userId != session.userId }
    if (foreignBinding == null && foreignPending == null) return true
    if (!pendingMarkerSaved || pendingRevocation == null) return false
    return foreignBinding == null ||
        (pendingRevocation.userId == foreignBinding.userId &&
            pendingRevocation.installationId == foreignBinding.installationId)
}

internal fun parseNotificationTapIntent(intent: Intent): PushPayload? {
    val extras = intent.extras ?: return null
    val keys = extras.keySet()
    val isSocial = keys == SOCIAL_TAP_EXTRA_KEYS
    val isLive = keys == LIVE_TAP_EXTRA_KEYS
    if (!isSocial && !isLive) return null
    val data = keys.associate { key ->
        key.removePrefix(TAP_EXTRA_PREFIX) to (extras.getString(key) ?: return null)
    }
    val payload = parsePushPayload(data, hasNotificationPayload = false) ?: return null
    return payload.takeIf { intent.action == pushTapAction(it) }
}

internal fun putPushPayloadExtras(intent: Intent, payload: PushPayload) {
    intent.putExtra("${TAP_EXTRA_PREFIX}version", PUSH_CONTRACT_VERSION.toString())
    intent.putExtra("${TAP_EXTRA_PREFIX}bindingId", payload.bindingId)
    when (payload) {
        is PushPayload.Social -> {
            intent.putExtra("${TAP_EXTRA_PREFIX}type", payload.type.wireValue)
            intent.putExtra("${TAP_EXTRA_PREFIX}objectId", payload.objectId)
            intent.putExtra(
                "${TAP_EXTRA_PREFIX}objectRevision",
                payload.objectRevision.toString()
            )
        }

        is PushPayload.Live -> {
            intent.putExtra("${TAP_EXTRA_PREFIX}kind", payload.kind.wireValue)
            intent.putExtra("${TAP_EXTRA_PREFIX}roomId", payload.roomId)
            intent.putExtra("${TAP_EXTRA_PREFIX}roomRevision", payload.objectRevision.toString())
        }
    }
}

internal fun pushTapAction(payload: PushPayload): String =
    "$PUSH_TAP_ACTION_PREFIX.${pushPayloadDigest(payload).take(24)}"

internal fun pushNotificationTag(payload: PushPayload): String =
    "$PUSH_NOTIFICATION_TAG_PREFIX${pushDisplayIdentityDigest(payload).take(32)}"

private fun pushPendingIntentRequestCode(payload: PushPayload): Int {
    val digest = MessageDigest.getInstance("SHA-256")
        .digest(pushPayloadIdentity(payload).toByteArray(Charsets.UTF_8))
    return ((digest[0].toInt() and 0xff) shl 24) or
        ((digest[1].toInt() and 0xff) shl 16) or
        ((digest[2].toInt() and 0xff) shl 8) or
        (digest[3].toInt() and 0xff)
}

private fun pushPayloadDigest(payload: PushPayload): String =
    MessageDigest.getInstance("SHA-256")
        .digest(pushPayloadIdentity(payload).toByteArray(Charsets.UTF_8))
        .joinToString(separator = "") { byte -> "%02x".format(byte) }

private fun pushDisplayIdentityDigest(payload: PushPayload): String =
    MessageDigest.getInstance("SHA-256")
        .digest(
            "${payload.bindingId}:${pushDisplayObjectKey(payload)}".toByteArray(Charsets.UTF_8)
        )
        .joinToString(separator = "") { byte -> "%02x".format(byte) }

private fun pushPayloadIdentity(payload: PushPayload): String = when (payload) {
    is PushPayload.Social ->
        "social:${payload.type.wireValue}:${payload.objectId}:${payload.objectRevision}:${payload.bindingId}"
    is PushPayload.Live ->
        "live:${payload.kind.wireValue}:${payload.roomId}:${payload.objectRevision}:${payload.bindingId}"
}

private const val TAP_EXTRA_PREFIX = "com.setforge.gymapp.push."
private const val PUSH_TAP_ACTION_PREFIX = "com.setforge.gymapp.action.PUSH_TAP"
private const val PUSH_NOTIFICATION_TAG_PREFIX = "gymapp_push:"
private val SOCIAL_TAP_EXTRA_KEYS = setOf(
    "${TAP_EXTRA_PREFIX}version",
    "${TAP_EXTRA_PREFIX}bindingId",
    "${TAP_EXTRA_PREFIX}type",
    "${TAP_EXTRA_PREFIX}objectId",
    "${TAP_EXTRA_PREFIX}objectRevision"
)
private val LIVE_TAP_EXTRA_KEYS = setOf(
    "${TAP_EXTRA_PREFIX}version",
    "${TAP_EXTRA_PREFIX}bindingId",
    "${TAP_EXTRA_PREFIX}kind",
    "${TAP_EXTRA_PREFIX}roomId",
    "${TAP_EXTRA_PREFIX}roomRevision"
)
