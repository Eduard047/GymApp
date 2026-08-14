package com.example.gymapp.auth

import com.example.gymapp.data.repository.SharedWorkoutExercise
import com.example.gymapp.data.repository.SharedWorkoutPlan
import com.example.gymapp.data.repository.SharedWorkoutSet
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SocialContractTest {
    @Test
    fun shortFriendCodeParsesExactlyAndNormalizesRawHumanAndLegacyForms() {
        val parsed = parseSocialMyFriendCode(
            """{"version":1,"friendCode":"g_a1b2c3d4e5f6"}"""
        )

        assertEquals(1, parsed.version)
        assertEquals("g_a1b2c3d4e5f6", parsed.friendCode)
        assertEquals("g_a1b2c3d4e5f6", normalizeSocialFriendCode(" G_A1B2C3D4E5F6 "))
        assertEquals(
            "g_a1b2c3d4e5f6",
            normalizeSocialFriendCode("gym-a1b2-c3d4-e5f6")
        )
        val legacy = profileId('a')
        assertEquals(legacy, normalizeSocialFriendCode(legacy.uppercase()))
        assertEquals("GYM-A1B2-C3D4-E5F6", formatSocialFriendCode(parsed.friendCode))
        assertEquals(legacy, formatSocialFriendCode(legacy))
    }

    @Test
    fun shortFriendCodeRejectsMalformedOrExpandedRpcResponses() {
        listOf(
            """{"version":2,"friendCode":"g_a1b2c3d4e5f6"}""",
            """{"version":1,"friendCode":"g_A1B2C3D4E5F6"}""",
            """{"version":1,"friendCode":"g_a1b2"}""",
            """{"version":1,"friendCode":"g_a1b2c3d4e5f6","extra":true}""",
            """[{"version":1,"friendCode":"g_a1b2c3d4e5f6"}]""",
            """{"version":1,"friendCode":"${"a".repeat(300)}"}"""
        ).forEach { raw ->
            assertThrows(IllegalArgumentException::class.java) {
                parseSocialMyFriendCode(raw)
            }
        }
        assertNull(normalizeSocialFriendCode("GYM-A1B2-C3D4"))
        assertNull(normalizeSocialFriendCode("GYM-A1B2-C3D4-E5G6"))
        assertNull(normalizeSocialFriendCode("g_a1b2c3d4e5f6_extra"))
        assertNull(normalizeSocialFriendCode("x".repeat(1_000)))
    }

    @Test
    fun dashboardParsesBoundedV1AndRanksOnlyAvailableFriendProgress() {
        val dashboardJson = validDashboard()
        dashboardJson.getJSONArray("friends").put(
            friend(
                friendshipId = friendshipId('2'),
                profileId = profileId('2'),
                displayName = "Private Friend",
                xp = null,
                level = null,
                workouts = null,
                progressShared = false,
                statsAvailable = false,
                progressUpdatedAt = null
            )
        )

        val parsed = parseSocialDashboard(dashboardJson.toString())

        assertEquals(profileId('0'), parsed.self.profileId)
        assertEquals(2, parsed.friends.size)
        assertEquals(profileId('1'), rankedSocialFriends(parsed.friends).first().profileId)
        assertEquals(1, parsed.pendingWorkoutInviteCount)
        assertFalse(parsed.friends.last().statsAvailable)
    }

    @Test
    fun dashboardRejectsCoercedNumbersExtraKeysAndOversizedArrays() {
        val coerced = validDashboard().apply {
            getJSONObject("self").put("xp", "900")
        }
        assertThrows(IllegalArgumentException::class.java) { parseSocialDashboard(coerced.toString()) }

        val extra = validDashboard().apply { put("userId", "secret-auth-id") }
        assertThrows(IllegalArgumentException::class.java) { parseSocialDashboard(extra.toString()) }

        val oversized = validDashboard().apply {
            put(
                "friends",
                JSONArray().also { array ->
                    repeat(SOCIAL_MAX_FRIENDS + 1) { index ->
                        array.put(
                            friend(
                                friendshipId = "f_${index.toString(16).padStart(32, '0')}",
                                profileId = "p_${(index + 1).toString(16).padStart(32, '0')}"
                            )
                        )
                    }
                }
            )
        }
        assertThrows(IllegalArgumentException::class.java) { parseSocialDashboard(oversized.toString()) }
    }

    @Test
    fun dashboardRejectsPrivateStatsThatLeakValuesAndDuplicateCrossListProfiles() {
        val leaked = validDashboard().apply {
            getJSONArray("friends").getJSONObject(0)
                .put("statsAvailable", false)
                .put("xp", 100)
        }
        assertThrows(IllegalArgumentException::class.java) { parseSocialDashboard(leaked.toString()) }

        val duplicated = validDashboard().apply {
            getJSONArray("incoming").put(
                friendRequest(friendshipId('3'), profileId('1'), "Same profile")
            )
        }
        assertThrows(IllegalArgumentException::class.java) { parseSocialDashboard(duplicated.toString()) }
    }

    @Test
    fun dashboardRequiresCanonicalSelfCodeAndTimestampForEveryAvailableStatsRow() {
        val wrongFriendCode = validDashboard().apply {
            getJSONObject("self").put("friendCode", profileId('e'))
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialDashboard(wrongFriendCode.toString())
        }

        val selfWithoutTimestamp = validDashboard().apply {
            getJSONObject("self").put("progressUpdatedAt", JSONObject.NULL)
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialDashboard(selfWithoutTimestamp.toString())
        }

        val friendWithoutTimestamp = validDashboard().apply {
            getJSONArray("friends").getJSONObject(0)
                .put("progressUpdatedAt", JSONObject.NULL)
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialDashboard(friendWithoutTimestamp.toString())
        }
    }

    @Test
    fun socialNamesPreserveNbspAtEdgesAndInsideButRejectAsciiSpaceEdges() {
        val nbspName = "\u00a0Current\u00a0User\u00a0"
        val dashboard = validDashboard().apply {
            getJSONObject("self").put("displayName", nbspName)
        }
        assertEquals(nbspName, parseSocialDashboard(dashboard.toString()).self.displayName)

        val inbox = validWorkoutInbox().apply {
            val incoming = getJSONArray("incoming").getJSONObject(0)
            incoming.getJSONObject("workout").getJSONArray("exercises").getJSONObject(0)
                .put("name", nbspName)
            incoming.getJSONObject("summary")
                .put("exerciseNames", JSONArray().put(nbspName))
        }
        val parsedInvite = parseSocialWorkoutInbox(inbox.toString()).incoming.single()
        assertEquals(nbspName, requireNotNull(parsedInvite.workout).exercises.single().name)
        assertEquals(nbspName, parsedInvite.summary.exerciseNames.single())

        val asciiEdgeDisplayName = validDashboard().apply {
            getJSONObject("self").put("displayName", " Current User")
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialDashboard(asciiEdgeDisplayName.toString())
        }

        val asciiEdgeExerciseName = validWorkoutInbox().apply {
            val incoming = getJSONArray("incoming").getJSONObject(0)
            incoming.getJSONObject("workout").getJSONArray("exercises").getJSONObject(0)
                .put("name", "Bench Press ")
            incoming.getJSONObject("summary")
                .put("exerciseNames", JSONArray().put("Bench Press "))
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInbox(asciiEdgeExerciseName.toString())
        }

        val whitespaceOnlyExerciseName = validWorkoutInbox().apply {
            val incoming = getJSONArray("incoming").getJSONObject(0)
            incoming.getJSONObject("workout").getJSONArray("exercises").getJSONObject(0)
                .put("name", "\u00a0")
            incoming.getJSONObject("summary")
                .put("exerciseNames", JSONArray().put("\u00a0"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInbox(whitespaceOnlyExerciseName.toString())
        }
    }

    @Test
    fun friendDetailsParseSelfReportedRecordsAndPrivateSectionsFailClosed() {
        val details = validFriendDetails()
        val parsed = parseSocialFriendDetails(details.toString())

        assertEquals("self_reported", parsed.integrity)
        assertEquals(1, parsed.recentWorkouts.size)
        assertEquals(100.5, parsed.exerciseRecords.single().bestWeightKg, 0.0)

        details.getJSONObject("sharing").put("records", false)
        assertThrows(IllegalArgumentException::class.java) { parseSocialFriendDetails(details.toString()) }

        val wrongIntegrity = validFriendDetails().put("integrity", "verified")
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialFriendDetails(wrongIntegrity.toString())
        }
    }

    @Test
    fun recentWorkoutAllowsTotalExerciseCountAboveTheTwentyVisibleLabels() {
        val details = validFriendDetails()
        val labels = JSONArray().also { array ->
            repeat(SOCIAL_MAX_WORKOUT_EXERCISES) { index ->
                array.put(
                    JSONObject()
                        .put("catalogKey", JSONObject.NULL)
                        .put("name", "Exercise ${index + 1}")
                )
            }
        }
        details.getJSONArray("recentWorkouts").put(
            0,
            JSONObject()
                .put("workoutDay", "2026-08-08")
                .put("exerciseCount", 25)
                .put("setCount", 125)
                .put("exercises", labels)
        )

        val workout = parseSocialFriendDetails(details.toString()).recentWorkouts.single()

        assertEquals(25, workout.exerciseCount)
        assertEquals(20, workout.exercises.size)
    }

    @Test
    fun friendDetailsRequireCoherentActivityTimestampAndUniqueRecordIdentities() {
        val missingTimestamp = validFriendDetails().put("activityUpdatedAt", JSONObject.NULL)
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialFriendDetails(missingTimestamp.toString())
        }

        val timestampWithoutSharing = validFriendDetails().apply {
            getJSONObject("sharing")
                .put("recentWorkouts", false)
                .put("records", false)
            put("recentWorkouts", JSONArray())
            put("exerciseRecords", JSONArray())
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialFriendDetails(timestampWithoutSharing.toString())
        }

        val duplicateWorkoutDay = validFriendDetails().apply {
            val workouts = getJSONArray("recentWorkouts")
            workouts.put(JSONObject(workouts.getJSONObject(0).toString()))
        }
        assertEquals(2, parseSocialFriendDetails(duplicateWorkoutDay.toString()).recentWorkouts.size)

        val duplicateRecordIdentity = validFriendDetails().apply {
            val records = getJSONArray("exerciseRecords")
            records.put(JSONObject(records.getJSONObject(0).toString()).put("name", "Renamed"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialFriendDetails(duplicateRecordIdentity.toString())
        }
    }

    @Test
    fun workoutInvitePayloadUsesExactCanonicalV1Shape() {
        val plan = SharedWorkoutPlan(
            exercises = listOf(
                SharedWorkoutExercise(
                    catalogKey = "bench_press",
                    name = "Bench Press",
                    sets = listOf(SharedWorkoutSet(100.5, 5), SharedWorkoutSet(90.0, 8))
                )
            )
        )

        val json = socialWorkoutJson(plan)
        val exercise = json.getJSONArray("exercises").getJSONObject(0)

        assertEquals(setOf("version", "exercises"), json.keys().asSequence().toSet())
        assertEquals(setOf("catalogKey", "name", "sets"), exercise.keys().asSequence().toSet())
        assertEquals(setOf("weight", "reps"),
            exercise.getJSONArray("sets").getJSONObject(0).keys().asSequence().toSet())
        assertTrue(json.toString().toByteArray().size <= SOCIAL_MAX_INVITE_JSON_BYTES)
    }

    @Test
    fun workoutInboxParsesIncomingPayloadButRejectsOutgoingPayloadAndSummaryMismatch() {
        val inbox = validWorkoutInbox()
        val parsed = parseSocialWorkoutInbox(inbox.toString())

        assertEquals(1, parsed.pendingIncomingCount)
        assertEquals(2, requireNotNull(parsed.incoming.single().workout).setCount)
        assertFalse(parsed.outgoing.single().let { it.status == "accepted" })

        val outgoingLeak = validWorkoutInbox().apply {
            getJSONArray("outgoing").getJSONObject(0).put("workout", workoutJson())
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInbox(outgoingLeak.toString())
        }

        val mismatch = validWorkoutInbox().apply {
            getJSONArray("incoming").getJSONObject(0)
                .getJSONObject("summary")
                .put("setCount", 3)
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInbox(mismatch.toString())
        }

        val duplicateCatalog = validWorkoutInbox().apply {
            val incoming = getJSONArray("incoming").getJSONObject(0)
            incoming.getJSONObject("workout").getJSONArray("exercises").put(
                JSONObject()
                    .put("catalogKey", "bench_press")
                    .put("name", "Different custom name")
                    .put("sets", JSONArray().put(JSONObject().put("weight", 1).put("reps", 1)))
            )
            incoming.put(
                "summary",
                JSONObject()
                    .put("exerciseCount", 2)
                    .put("setCount", 3)
                    .put(
                        "exerciseNames",
                        JSONArray().put("Bench Press").put("Different custom name")
                    )
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInbox(duplicateCatalog.toString())
        }
    }

    @Test
    fun boundedWorkoutInboxPageIsMetadataOnlyAndKeepsItsStableCursor() {
        val page = validWorkoutInbox().apply {
            put("version", 2)
            put("pendingIncomingCount", 3)
            getJSONArray("incoming").getJSONObject(0).remove("workout")
            put(
                "nextCursor",
                JSONObject()
                    .put("createdAt", TIMESTAMP)
                    .put("inviteId", inviteId('1'))
                    .put("pending", true)
            )
        }

        val parsed = parseSocialWorkoutInboxPage(page.toString(), expectedLimit = 1)

        assertNull(parsed.incoming.single().workout)
        assertEquals(3, parsed.pendingIncomingCount)
        assertEquals(inviteId('1'), parsed.nextCursor?.inviteId)
        assertFalse(parsed.usesLegacyFullPayload)

        page.getJSONArray("incoming").getJSONObject(0).put("workout", workoutJson())
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInboxPage(page.toString(), expectedLimit = 1)
        }
    }

    @Test
    fun boundedWorkoutInboxPageRejectsShortCursorPagesAndCursorOrOrderDrift() {
        val page = validWorkoutInbox().apply {
            put("version", 2)
            getJSONArray("incoming").getJSONObject(0).remove("workout")
            put(
                "nextCursor",
                JSONObject()
                    .put("createdAt", TIMESTAMP)
                    .put("inviteId", inviteId('1'))
                    .put("pending", true)
            )
        }

        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInboxPage(page.toString())
        }

        page.getJSONObject("nextCursor").put("inviteId", inviteId('2'))
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInboxPage(page.toString(), expectedLimit = 1)
        }

        val first = page.getJSONArray("incoming").getJSONObject(0)
        val second = JSONObject(first.toString())
            .put("inviteId", inviteId('3'))
            .put("profileId", profileId('3'))
        page.put("incoming", JSONArray().put(first).put(second))
        page.put("nextCursor", JSONObject.NULL)
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInboxPage(page.toString(), expectedLimit = 2)
        }
    }

    @Test
    fun legacyWorkoutInboxValidatesThenCapsVisibleListsAtTwenty() {
        val inbox = validWorkoutInbox()
        val template = inbox.getJSONArray("incoming").getJSONObject(0)
        val incoming = JSONArray()
        repeat(21) { index ->
            val hex = (index + 1).toString(16).padStart(32, '0')
            incoming.put(
                JSONObject(template.toString())
                    .put("inviteId", "wi_$hex")
                    .put("profileId", "p_$hex")
            )
        }
        inbox.put("incoming", incoming)
        inbox.put("pendingIncomingCount", 21)

        val parsed = parseSocialWorkoutInbox(inbox.toString())

        assertEquals(20, parsed.incoming.size)
        assertEquals(21, parsed.pendingIncomingCount)
        assertTrue(parsed.usesLegacyFullPayload)
        assertNull(parsed.nextCursor)
    }

    @Test
    fun exactWorkoutInvitePlanRequiresExactEnvelopeAndBounds() {
        val raw = JSONObject()
            .put("version", 1)
            .put("inviteId", inviteId('1'))
            .put("inviteRevision", 4)
            .put("workout", workoutJson())

        val plan = parseSocialWorkoutInvitePlan(raw.toString())

        assertEquals(inviteId('1'), plan.inviteId)
        assertEquals(4, plan.inviteRevision)
        assertEquals(2, plan.workout.setCount)

        raw.put("inviteRevision", 0)
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInvitePlan(raw.toString())
        }
    }

    @Test
    fun workoutInboxUsesServerPortableIdentityInsteadOfLocalBuiltInAliases() {
        val inbox = validWorkoutInbox().apply {
            val incoming = getJSONArray("incoming").getJSONObject(0)
            incoming.getJSONObject("workout").getJSONArray("exercises").put(
                JSONObject()
                    .put("catalogKey", "bench_press_uk")
                    .put("name", "Жим штанги лежачи")
                    .put("sets", JSONArray().put(JSONObject().put("weight", 80).put("reps", 8)))
            )
            incoming.put(
                "summary",
                JSONObject()
                    .put("exerciseCount", 2)
                    .put("setCount", 3)
                    .put(
                        "exerciseNames",
                        JSONArray().put("Bench Press").put("Жим штанги лежачи")
                    )
            )
        }

        val workout = requireNotNull(
            parseSocialWorkoutInbox(inbox.toString()).incoming.single().workout
        )

        assertEquals(listOf("Bench Press", "Жим штанги лежачи"), workout.exercises.map { it.name })
        assertEquals(listOf("bench_press", "bench_press_uk"), workout.exercises.map { it.catalogKey })
    }

    @Test
    fun workoutInboxRejectsNamesThatDuplicateUnderServerPortableNormalization() {
        listOf(
            "Café" to "Cafe\u0301",
            "Bench Press" to "\u00a0Bench\u00a0Press\u00a0",
            "Ёжʼ" to "ЕЖ'"
        ).forEach { (firstName, secondName) ->
            val inbox = validWorkoutInbox().apply {
                val incoming = getJSONArray("incoming").getJSONObject(0)
                val exercises = incoming.getJSONObject("workout").getJSONArray("exercises")
                exercises.getJSONObject(0)
                    .put("catalogKey", "portable_one")
                    .put("name", firstName)
                exercises.put(
                    JSONObject()
                        .put("catalogKey", "portable_two")
                        .put("name", secondName)
                        .put("sets", JSONArray().put(JSONObject().put("weight", 80).put("reps", 8)))
                )
                incoming.put(
                    "summary",
                    JSONObject()
                        .put("exerciseCount", 2)
                        .put("setCount", 3)
                        .put("exerciseNames", JSONArray().put(firstName).put(secondName))
                )
            }

            assertThrows(IllegalArgumentException::class.java) {
                parseSocialWorkoutInbox(inbox.toString())
            }
        }
    }

    @Test
    fun workoutInboxAcceptsOnlyLiveIncomingRowsAndCoherentResponseTimes() {
        val accepted = validWorkoutInbox().apply {
            getJSONArray("incoming").getJSONObject(0)
                .put("status", "accepted")
                .put("respondedAt", TIMESTAMP)
            put("pendingIncomingCount", 0)
        }
        assertEquals("accepted", parseSocialWorkoutInbox(accepted.toString()).incoming.single().status)

        val expiredIncoming = validWorkoutInbox().apply {
            getJSONArray("incoming").getJSONObject(0)
                .put("status", "expired")
                .put("respondedAt", TIMESTAMP)
            put("pendingIncomingCount", 0)
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInbox(expiredIncoming.toString())
        }

        val acceptedWithoutResponseTime = validWorkoutInbox().apply {
            getJSONArray("incoming").getJSONObject(0).put("status", "accepted")
            put("pendingIncomingCount", 0)
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInbox(acceptedWithoutResponseTime.toString())
        }

        val terminalOutgoingWithoutResponseTime = validWorkoutInbox().apply {
            getJSONArray("outgoing").getJSONObject(0).put("status", "declined")
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInbox(terminalOutgoingWithoutResponseTime.toString())
        }
    }

    @Test
    fun inviteMutationsRequirePayloadOnlyForAcceptedDecision() {
        val accepted = JSONObject()
            .put("version", 1)
            .put("inviteId", inviteId('1'))
            .put("status", "accepted")
            .put("inviteRevision", 2)
            .put("workout", workoutJson())
        assertEquals(2, parseSocialWorkoutInviteMutation(accepted.toString()).workout?.setCount)

        val declined = JSONObject(accepted.toString())
            .put("status", "declined")
            .put("workout", JSONObject.NULL)
        assertNull(parseSocialWorkoutInviteMutation(declined.toString()).workout)

        val acceptedWithoutWorkout = JSONObject(accepted.toString()).put("workout", JSONObject.NULL)
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialWorkoutInviteMutation(acceptedWithoutWorkout.toString())
        }
    }

    @Test
    fun identifiersAndFriendCodesAreStrictAndCanonical() {
        assertEquals(profileId('a'), normalizeSocialFriendCode("  ${profileId('a').uppercase()}  "))
        assertNull(normalizeSocialFriendCode("p_short"))
        assertTrue(isValidSocialWorkoutInviteId(inviteId('f')))
        assertFalse(isValidSocialWorkoutInviteId("wi_${"F".repeat(32)}"))
        assertTrue(isValidSocialClientRequestId("123e4567-e89b-42d3-a456-426614174000"))
        assertFalse(isValidSocialClientRequestId("123E4567-E89B-42D3-A456-426614174000"))
    }

    @Test
    fun friendWorkoutPageIsExactBoundedReadOnlyAndAllowsBodyweightSets() {
        val parsed = parseSocialFriendWorkoutPage(validFriendWorkoutPage().toString())

        assertEquals(profileId('1'), parsed.profileId)
        assertEquals(TIMESTAMP, parsed.activityRevision)
        assertNull(parsed.nextCursor)
        assertEquals(0.0, parsed.items.single().exercises.single().sets.first().weightKg, 0.0)
        assertEquals(12, parsed.items.single().exercises.single().sets.first().reps)

        val expanded = validFriendWorkoutPage().put("privateNote", "must stay private")
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialFriendWorkoutPage(expanded.toString())
        }

        val cursor = validFriendWorkoutPage().put("nextCursor", "123:1")
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialFriendWorkoutPage(cursor.toString())
        }

        val oversizedSets = validFriendWorkoutPage().apply {
            val sets = getJSONArray("items").getJSONObject(0)
                .getJSONArray("exercises").getJSONObject(0).getJSONArray("sets")
            repeat(20) { sets.put(JSONObject().put("weightKg", 1).put("reps", 1)) }
            getJSONArray("items").getJSONObject(0).put("setCount", 21)
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialFriendWorkoutPage(oversizedSets.toString())
        }

        val nonNumericWeight = validFriendWorkoutPage().apply {
            getJSONArray("items").getJSONObject(0)
                .getJSONArray("exercises").getJSONObject(0)
                .getJSONArray("sets").getJSONObject(0).put("weightKg", "0")
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseSocialFriendWorkoutPage(nonNumericWeight.toString())
        }
    }

    @Test
    fun detailPrivacyCapabilityAndRealtimeInvalidationAreExact() {
        val privacy = parseSocialWorkoutDetailPrivacy(
            """{"version":1,"shareWorkoutDetails":false,"settingsRevision":7}"""
        )
        assertFalse(privacy.shareWorkoutDetails)
        assertEquals(7, privacy.settingsRevision)
        assertFalse(parseSocialFriendWorkoutDetailCapability(
            """{"version":1,"available":false}"""
        ).available)
        assertEquals(
            "privacy_changed",
            parseSocialRealtimeSignal(
                """{"version":1,"kind":"privacy_changed"}"""
            ).kind
        )

        listOf(
            """{"version":1,"available":false,"profileId":"${profileId('1')}"}""",
            """{"version":1,"kind":"privacy_changed","settingsRevision":7}""",
            """{"version":1,"shareWorkoutDetails":false,"settingsRevision":0}"""
        ).forEach { raw ->
            assertThrows(IllegalArgumentException::class.java) {
                when {
                    raw.contains("available") -> parseSocialFriendWorkoutDetailCapability(raw)
                    raw.contains("kind") -> parseSocialRealtimeSignal(raw)
                    else -> parseSocialWorkoutDetailPrivacy(raw)
                }
            }
        }
    }

    private fun validFriendWorkoutPage(): JSONObject = JSONObject()
        .put("version", 1)
        .put(
            "friend",
            JSONObject()
                .put("profileId", profileId('1'))
                .put("displayName", "Training Friend")
        )
        .put("activityRevision", TIMESTAMP)
        .put(
            "items",
            JSONArray().put(
                JSONObject()
                    .put("workoutId", "fw_${"1".repeat(32)}")
                    .put("startedAt", TIMESTAMP)
                    .put("workoutDay", "2026-08-09")
                    .put("exerciseCount", 1)
                    .put("setCount", 1)
                    .put("truncated", false)
                    .put(
                        "exercises",
                        JSONArray().put(
                            JSONObject()
                                .put("catalogKey", "push_up")
                                .put("name", "Push Up")
                                .put(
                                    "sets",
                                    JSONArray().put(
                                        JSONObject().put("weightKg", 0).put("reps", 12)
                                    )
                                )
                        )
                    )
            )
        )
        .put("nextCursor", JSONObject.NULL)
        .put("integrity", "self_reported")

    private fun validDashboard(): JSONObject = JSONObject()
        .put("version", 1)
        .put(
            "self",
            JSONObject()
                .put("profileId", profileId('0'))
                .put("friendCode", profileId('0'))
                .put("displayName", "Current User")
                .put("xp", 800)
                .put("level", 4)
                .put("workouts", 12)
                .put("statsAvailable", true)
                .put("progressUpdatedAt", TIMESTAMP)
                .put("privacy", privacy())
                .put("settingsRevision", 3)
        )
        .put(
            "friends",
            JSONArray().put(friend(friendshipId('1'), profileId('1')))
        )
        .put("incoming", JSONArray())
        .put("outgoing", JSONArray())
        .put("blocked", JSONArray())
        .put("pendingWorkoutInviteCount", 1)

    private fun friend(
        friendshipId: String,
        profileId: String,
        displayName: String = "Training Friend",
        xp: Int? = 1200,
        level: Int? = 5,
        workouts: Int? = 20,
        progressShared: Boolean = true,
        statsAvailable: Boolean = true,
        progressUpdatedAt: String? = TIMESTAMP
    ): JSONObject = JSONObject()
        .put("friendshipId", friendshipId)
        .put("profileId", profileId)
        .put("displayName", displayName)
        .put("xp", xp ?: JSONObject.NULL)
        .put("level", level ?: JSONObject.NULL)
        .put("workouts", workouts ?: JSONObject.NULL)
        .put("progressShared", progressShared)
        .put("statsAvailable", statsAvailable)
        .put("progressUpdatedAt", progressUpdatedAt ?: JSONObject.NULL)
        .put("friendshipRevision", 2)
        .put("status", "accepted")

    private fun friendRequest(friendshipId: String, profileId: String, name: String): JSONObject =
        JSONObject()
            .put("friendshipId", friendshipId)
            .put("profileId", profileId)
            .put("displayName", name)
            .put("requestedAt", TIMESTAMP)
            .put("friendshipRevision", 1)
            .put("status", "pending")

    private fun validFriendDetails(): JSONObject = JSONObject()
        .put("version", 1)
        .put(
            "friend",
            JSONObject()
                .put("profileId", profileId('1'))
                .put("displayName", "Training Friend")
                .put("xp", 1200)
                .put("level", 5)
                .put("workouts", 20)
                .put("progressShared", true)
                .put("statsAvailable", true)
                .put("progressUpdatedAt", TIMESTAMP)
        )
        .put(
            "sharing",
            JSONObject()
                .put("progress", true)
                .put("recentWorkouts", true)
                .put("records", true)
        )
        .put("activityUpdatedAt", TIMESTAMP)
        .put(
            "recentWorkouts",
            JSONArray().put(
                JSONObject()
                    .put("workoutDay", "2026-08-08")
                    .put("exerciseCount", 1)
                    .put("setCount", 2)
                    .put(
                        "exercises",
                        JSONArray().put(
                            JSONObject().put("catalogKey", "bench_press").put("name", "Bench Press")
                        )
                    )
            )
        )
        .put(
            "exerciseRecords",
            JSONArray().put(
                JSONObject()
                    .put("catalogKey", "bench_press")
                    .put("name", "Bench Press")
                    .put("bestWeightKg", 100.5)
                    .put("bestReps", 5)
                    .put("workoutCount", 4)
                    .put("lastWorkoutDay", "2026-08-08")
            )
        )
        .put("integrity", "self_reported")

    private fun validWorkoutInbox(): JSONObject = JSONObject()
        .put("version", 1)
        .put("pendingIncomingCount", 1)
        .put(
            "incoming",
            JSONArray().put(
                JSONObject()
                    .put("inviteId", inviteId('1'))
                    .put("profileId", profileId('1'))
                    .put("displayName", "Training Friend")
                    .put("status", "pending")
                    .put("inviteRevision", 1)
                    .put("createdAt", TIMESTAMP)
                    .put("expiresAt", "2026-08-10T10:00:00Z")
                    .put("respondedAt", JSONObject.NULL)
                    .put("summary", workoutSummary())
                    .put("workout", workoutJson())
            )
        )
        .put(
            "outgoing",
            JSONArray().put(
                JSONObject()
                    .put("inviteId", inviteId('2'))
                    .put("profileId", profileId('2'))
                    .put("displayName", "Other Friend")
                    .put("status", "pending")
                    .put("inviteRevision", 1)
                    .put("createdAt", TIMESTAMP)
                    .put("expiresAt", "2026-08-10T10:00:00Z")
                    .put("respondedAt", JSONObject.NULL)
                    .put("summary", workoutSummary())
            )
        )

    private fun workoutSummary(): JSONObject = JSONObject()
        .put("exerciseCount", 1)
        .put("setCount", 2)
        .put("exerciseNames", JSONArray().put("Bench Press"))

    private fun workoutJson(): JSONObject = JSONObject()
        .put("version", 1)
        .put(
            "exercises",
            JSONArray().put(
                JSONObject()
                    .put("catalogKey", "bench_press")
                    .put("name", "Bench Press")
                    .put(
                        "sets",
                        JSONArray()
                            .put(JSONObject().put("weight", 100.5).put("reps", 5))
                            .put(JSONObject().put("weight", 90.0).put("reps", 8))
                    )
            )
        )

    private fun privacy(): JSONObject = JSONObject()
        .put("allowRequests", true)
        .put("shareProgress", true)
        .put("shareRecentWorkouts", true)
        .put("shareRecords", true)

    private fun profileId(character: Char): String = "p_${character.toString().repeat(32)}"
    private fun friendshipId(character: Char): String = "f_${character.toString().repeat(32)}"
    private fun inviteId(character: Char): String = "wi_${character.toString().repeat(32)}"

    private companion object {
        const val TIMESTAMP = "2026-08-09T10:00:00Z"
    }
}
