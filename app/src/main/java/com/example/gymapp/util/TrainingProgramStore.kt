package com.example.gymapp.util

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.time.*

data class TrainingProgramSlot(val id: Long, val date: Long, val sessionId: Long? = null)
data class TrainingProgram(val id: Long, val createdAt: Long, val days: Int, val goal: String,
                           val status: String, val slots: List<TrainingProgramSlot>)

class TrainingProgramStore(context: Context, private val owner: String) {
    private val preferences = context.getSharedPreferences("training-program-v1", Context.MODE_PRIVATE)
    private val key = "program:$owner"
    init { require(owner.length in 1..128 && owner.toByteArray().size <= 512) }

    fun load(): TrainingProgram? = preferences.getString(key, null)?.takeIf { it.toByteArray().size <= 32_768 }?.let { TrainingProgramCodec.decode(it, owner) }
    fun clear(): Boolean = preferences.edit().remove(key).commit() && !preferences.contains(key)
    fun save(program: TrainingProgram): Boolean {
        val encoded = TrainingProgramCodec.encode(program, owner) ?: return false
        return preferences.edit().putString(key, encoded).commit() && preferences.getString(key, null) == encoded
    }
    fun create(days: Int, goal: String, now: Long = System.currentTimeMillis()): Boolean {
        require(days in 2..6 && goal.length <= 64)
        val offsets = mapOf(2 to listOf(0,3),3 to listOf(0,2,4),4 to listOf(0,1,3,5),5 to listOf(0,1,2,3,4),6 to listOf(0,1,2,3,4,5)).getValue(days)
        val start = Instant.ofEpochMilli(now).atZone(ZoneId.systemDefault()).toLocalDate()
        var nextId = now.coerceAtLeast(1); val slots = mutableListOf<TrainingProgramSlot>()
        repeat(4) { week -> offsets.forEach { offset -> slots += TrainingProgramSlot(nextId++, start.plusDays((week*7+offset).toLong()).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()) } }
        return save(TrainingProgram(now.coerceAtLeast(1), now, days, goal, "active", slots))
    }
    fun updateStatus(status: String): Boolean { val p=load()?:return false; if(p.status=="completed"||status !in setOf("active","paused","completed"))return false;return save(p.copy(status=status)) }
    fun next(program: TrainingProgram? = null): TrainingProgramSlot? { val resolved=program ?: load() ?: return null; return resolved.slots.firstOrNull{it.sessionId==null} }
    fun matchingSession(program: TrainingProgram, slot: TrainingProgramSlot, sessions: List<com.example.gymapp.data.entity.WorkoutSessionSummary>): com.example.gymapp.data.entity.WorkoutSessionSummary? {
        val i=program.slots.indexOfFirst{it.id==slot.id};if(i<0)return null;val until=program.slots.getOrNull(i+1)?.date?:slot.date+7*86_400_000L;val used=program.slots.mapNotNull{it.sessionId}.toSet()
        return sessions.filter{it.session.date>=slot.date&&it.session.date<until&&it.session.id !in used}.maxByOrNull{it.session.date}
    }
    fun link(sessionId: Long, sessions: List<com.example.gymapp.data.entity.WorkoutSessionSummary>): Boolean { val p=load()?.takeIf { it.status=="active" }?:return false;val slot=next(p)?:return false;val match=matchingSession(p,slot,sessions)?:return false;if(match.session.id!=sessionId)return false;val slots=p.slots.map{if(it.id==slot.id)it.copy(sessionId=sessionId)else it};return save(p.copy(status=if(slots.all{it.sessionId!=null})"completed"else p.status,slots=slots)) }
    fun rescheduleNext(): Boolean {
        val program = load()?.takeIf { it.status == "active" } ?: return false
        val slot = next(program) ?: return false
        val zone = ZoneId.systemDefault()
        val used = program.slots.filter { it.id != slot.id }.map { it.date }.toSet()
        var day = LocalDate.now().plusDays(1)
        while (day.atStartOfDay(zone).toInstant().toEpochMilli() in used) day = day.plusDays(1)
        val date = day.atStartOfDay(zone).toInstant().toEpochMilli()
        return save(program.copy(slots = program.slots.map {
            if (it.id == slot.id) it.copy(date = date) else it
        }.sortedBy { it.date }))
    }
}

internal object TrainingProgramCodec {
    private const val MAX_BYTES = 32_768
    private val rootKeys = setOf("version", "owner", "id", "createdAt", "days", "goal", "status", "slots")
    private val slotKeys = setOf("id", "date", "sessionId")

    fun encode(program: TrainingProgram, owner: String): String? = runCatching {
        validate(program)
        require(owner.length in 1..128 && owner.toByteArray().size <= 512)
        JSONObject().put("version", 1).put("owner", owner).put("id", program.id)
            .put("createdAt", program.createdAt).put("days", program.days)
            .put("goal", program.goal).put("status", program.status)
            .put("slots", JSONArray().also { slots -> program.slots.forEach { slot ->
                slots.put(JSONObject().put("id", slot.id).put("date", slot.date)
                    .put("sessionId", slot.sessionId ?: JSONObject.NULL))
            } }).toString().also { require(it.toByteArray().size <= MAX_BYTES) }
    }.getOrNull()

    fun decode(raw: String, owner: String): TrainingProgram? = runCatching {
        require(raw.toByteArray().size <= MAX_BYTES)
        val root = JSONObject(raw)
        require(root.keys().asSequence().toSet() == rootKeys)
        require(integer(root, "version") == 1L && root.get("owner") == owner)
        val days = integer(root, "days")
        require(days in 2..6)
        val array = root.getJSONArray("slots")
        require(array.length() == days.toInt() * 4)
        val slots = (0 until array.length()).map { index ->
            val slot = array.getJSONObject(index)
            require(slot.keys().asSequence().toSet() == slotKeys)
            TrainingProgramSlot(integer(slot, "id"), integer(slot, "date"),
                if (slot.isNull("sessionId")) null else integer(slot, "sessionId"))
        }
        TrainingProgram(integer(root, "id"), integer(root, "createdAt"), days.toInt(),
            root.get("goal") as String, root.get("status") as String, slots).also(::validate)
    }.getOrNull()

    private fun integer(objectValue: JSONObject, key: String): Long {
        val value = objectValue.get(key)
        require(value is Int || value is Long)
        return (value as Number).toLong()
    }

    private fun validate(program: TrainingProgram) {
        val now = System.currentTimeMillis()
        require(program.id > 0 && program.createdAt in 1..now && program.days in 2..6)
        require(program.goal.length <= 64 && program.status in setOf("active", "paused", "completed"))
        require(program.slots.size == program.days * 4)
        require(program.slots.map { it.id }.distinct().size == program.slots.size)
        require(program.slots.zipWithNext().all { it.first.date < it.second.date })
        require(program.slots.all {
            it.id > 0 && it.date in -62135769600000L..minOf(64092211200000L, now + 40 * 86_400_000L) &&
                (it.sessionId == null || it.sessionId > 0)
        })
        require(program.slots.mapNotNull { it.sessionId }.distinct().size == program.slots.count { it.sessionId != null })
    }
}
