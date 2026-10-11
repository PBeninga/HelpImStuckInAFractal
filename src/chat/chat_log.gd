class_name ChatLog
extends RefCounted
## The pilot chat between the person and the agent: an ordered list of
## messages plus what the agent is doing. Held by McpBridge so it outlives a
## scene change; ChatPanel shows it, the bridge's chat_* commands feed it.
##
## A message is {id, role, text, source, time}: role "human", "agent" or
## "system"; source says how a human message arrived ("typed" today, "voice"
## once speech-to-text posts through the bridge's chat_post).

signal message_added(message: Dictionary)
signal cleared
signal state_changed
## Text in progress (a live voice transcript), shown in the panel's input box.
signal draft_changed(text: String)

enum AgentState { OFFLINE, LISTENING, WORKING }

const MAX_MESSAGES := 500

var messages: Array = []
## The last human message id handed to the agent.
var agent_cursor := 0
## Requests currently waiting for a human message (wait_for_message calls).
var listeners := 0:
	set(v):
		listeners = maxi(v, 0)
		state_changed.emit()
## True from handing the agent a message until it next listens.
var busy := false:
	set(v):
		if v != busy:
			busy = v
			state_changed.emit()

var _next_id := 1


func add(role: String, text: String, source := "") -> Dictionary:
	var m := {
		"id": _next_id, "role": role, "text": text, "source": source,
		"time": Time.get_unix_time_from_system(),
	}
	_next_id += 1
	messages.append(m)
	if messages.size() > MAX_MESSAGES:
		messages.remove_at(0)
	message_added.emit(m)
	return m


## Human messages with an id above `after`.
func human_after(after: int) -> Array:
	return messages.filter(func(m): return m["role"] == "human" and m["id"] > after)


func recent(limit: int) -> Array:
	return messages.slice(maxi(0, messages.size() - limit))


func clear() -> void:
	messages.clear()
	cleared.emit()


func set_draft(text: String) -> void:
	draft_changed.emit(text)


func agent_state() -> AgentState:
	if busy:
		return AgentState.WORKING
	if listeners > 0:
		return AgentState.LISTENING
	return AgentState.OFFLINE
