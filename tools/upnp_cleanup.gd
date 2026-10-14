# Referme le port du jeu sur la box (UPnP) s'il est resté ouvert.
# Lancer : Godot --headless --path . --script res://tools/upnp_cleanup.gd
extends SceneTree


func _initialize() -> void:
	var upnp := UPNP.new()
	if upnp.discover(2000, 2, "InternetGatewayDevice") != UPNP.UPNP_RESULT_SUCCESS:
		print("Box introuvable (UPnP).")
	else:
		var result := upnp.delete_port_mapping(7777, "UDP")
		print("Port 7777 encore ouvert : refermé." if result == UPNP.UPNP_RESULT_SUCCESS else "Port 7777 déjà fermé (code %d)." % result)
	quit()
