extends RefCounted

static func read_keys() -> Dictionary:
 return {"a":Input.is_physical_key_pressed(KEY_A),"d":Input.is_physical_key_pressed(KEY_D),"w":Input.is_physical_key_pressed(KEY_W),"f":Input.is_physical_key_pressed(KEY_F),"left":Input.is_physical_key_pressed(KEY_LEFT),"right":Input.is_physical_key_pressed(KEY_RIGHT),"up":Input.is_physical_key_pressed(KEY_UP),"l":Input.is_physical_key_pressed(KEY_L)}

static func split(keys: Dictionary, player: int) -> Array:
 if player == 1: return [float(keys.get("d",false))-float(keys.get("a",false)),keys.get("w",false),keys.get("f",false)]
 return [float(keys.get("right",false))-float(keys.get("left",false)),keys.get("up",false),keys.get("l",false)]
