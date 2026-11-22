class_name GameEventBus
extends Node
## Lightweight notification fan-out for UI and presentation (spec §4.2). Signals here are NOT a
## source of truth: they are re-broadcasts of DomainEvents that a CommandProcessor has already
## committed. Persisted/replayable facts live in WorldState and DomainEvents.
## Registered as the `EventBus` autoload; tests create their own instances.

signal domain_event_published(event: DomainEvent)
signal time_advanced(old_minute: int, new_minute: int)
signal day_changed(day_index: int)
signal wallet_changed(owner_id: String, balance_minor: int)
signal need_changed(owner_id: String, need_id: String, value: int)
signal inventory_changed(owner_id: String, item_id: String, count: int)
signal activity_completed(activity_id: String, ended_minute: int)
## Not a DomainEvent: saving does not change the world (emitted by GameSession).
signal save_completed(slot_id: String)


func attach(processor: CommandProcessor) -> void:
	if not processor.committed.is_connected(_on_committed):
		processor.committed.connect(_on_committed)


func detach(processor: CommandProcessor) -> void:
	if processor.committed.is_connected(_on_committed):
		processor.committed.disconnect(_on_committed)


func publish(events: Array[DomainEvent]) -> void:
	for e in events:
		domain_event_published.emit(e)
		match e.type:
			"time_advanced":
				time_advanced.emit(int(e.payload["old_minute"]), int(e.payload["new_minute"]))
			"day_changed":
				day_changed.emit(int(e.payload["day_index"]))
			"wallet_changed":
				wallet_changed.emit(str(e.payload["owner_id"]), int(e.payload["balance_minor"]))
			"need_changed":
				need_changed.emit(str(e.payload["owner_id"]), str(e.payload["need_id"]), int(e.payload["value"]))
			"inventory_changed":
				inventory_changed.emit(str(e.payload["owner_id"]), str(e.payload["item_id"]), int(e.payload["count"]))
			"activity_completed":
				activity_completed.emit(str(e.payload["activity_id"]), int(e.payload["ended_minute"]))


func _on_committed(_result: CommandResult, events: Array[DomainEvent]) -> void:
	publish(events)
