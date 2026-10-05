# Tests unitaires des règles.
# Lancer : Godot --headless --path . --script res://tests/test_rules.gd
extends SceneTree

const GameRules = preload("res://scripts/game_rules.gd")

var failures := 0


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	var rules := GameRules.new()
	rules.setup(4, rng)
	_expect(rules.counts() == [13, 13, 13, 13], "distribution 13 cartes chacun")

	# Partage du tas entre deux joueurs qui n'ont pas tapé.
	for i in 5:
		rules.play(i % 4)
	var losers: Array[int] = [2, 0]
	var shares := rules.give_center_to(losers, rng)
	_expect(shares == {2: 3, 0: 2}, "partage de 5 cartes entre 2 joueurs : %s" % shares)
	_expect(rules.center.is_empty(), "le centre est vide après partage")
	_expect(rules.total_cards() == 52, "52 cartes après partage")

	print("OK" if failures == 0 else "%d ÉCHEC(S)" % failures)
	quit(failures)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("ÉCHEC : " + label)
