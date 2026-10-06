# Tests unitaires des règles.
# Lancer : Godot --headless --path . --script res://tests/test_rules.gd
extends SceneTree

const GameRules = preload("res://scripts/game_rules.gd")
const Cards = preload("res://scripts/cards.gd")

var failures := 0


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	var rules := GameRules.new()
	rules.setup(4, rng)
	_expect(rules.counts() == [13, 13, 13, 13], "distribution 13 cartes chacun")
	var rules5 := GameRules.new()
	rules5.setup(5, rng)
	_expect(rules5.counts() == [10, 10, 10, 10, 10] and rules5.cards_in_play == 50, "à 5 joueurs : tas égaux de 10, 2 cartes de côté")

	# Partage du tas entre deux joueurs qui n'ont pas tapé.
	for i in 5:
		rules.play(i % 4)
	var losers: Array[int] = [2, 0]
	var shares := rules.give_center_to(losers, rng)
	_expect(shares == {2: 3, 0: 2}, "partage de 5 cartes entre 2 joueurs : %s" % shares)
	_expect(rules.center.is_empty(), "le centre est vide après partage")
	_expect(rules.total_cards() == 52, "52 cartes après partage")

	# Paires : même valeur, ou deux têtes (valet = 10, dame = 11, roi = 12 ; + 13 par couleur).
	_expect(Cards.forms_pair(4, 17), "deux 5 forment une paire")
	_expect(Cards.forms_pair(10, 25), "valet + roi forment une paire")
	_expect(Cards.forms_pair(11, 37), "dame + valet forment une paire")
	_expect(not Cards.forms_pair(9, 10), "10 + valet ne forment pas une paire")
	_expect(not Cards.forms_pair(0, 12), "as + roi ne forment pas une paire")

	# Paire recouverte puis éjection de la carte du dessus.
	rules.center.assign([4, 17, 31])
	_expect(not rules.is_pair() and rules.is_covered_pair(), "paire recouverte détectée")
	var before := rules.count(1)
	var ejected := rules.eject_top_to(1)
	_expect(ejected == 31 and rules.is_pair(), "éjection : la paire redevient visible")
	_expect(rules.count(1) == before + 1 and rules.piles[1][-1] == 31, "la carte éjectée va sous le tas")

	print("OK" if failures == 0 else "%d ÉCHEC(S)" % failures)
	quit(failures)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("ÉCHEC : " + label)
