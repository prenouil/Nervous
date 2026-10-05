# État pur d'une partie : tas des joueurs et tas du centre.
# Aucune notion de temps ni d'affichage ici (voir game_server.gd).

const Cards = preload("res://scripts/cards.gd")

var num_players := 4
var piles: Array = []          # piles[p] : Array[int], index 0 = carte du dessus
var center: Array[int] = []    # dernier élément = carte visible


func setup(players: int, rng: RandomNumberGenerator) -> void:
	num_players = players
	var deck: Array[int] = []
	for c in 52:
		deck.append(c)
	shuffle(deck, rng)
	piles.clear()
	for p in players:
		var pile: Array[int] = []
		piles.append(pile)
	for i in deck.size():
		piles[i % players].append(deck[i])
	center.clear()


static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func count(p: int) -> int:
	return piles[p].size()


func counts() -> Array:
	var result := []
	for p in num_players:
		result.append(count(p))
	return result


func total_cards() -> int:
	var total := center.size()
	for p in num_players:
		total += count(p)
	return total


func play(p: int) -> int:
	var card: int = piles[p].pop_front()
	center.append(card)
	return card


func is_pair() -> bool:
	var n := center.size()
	return n >= 2 and Cards.rank(center[n - 1]) == Cards.rank(center[n - 2])


# Le tas du centre est mélangé et placé sous le tas du joueur.
func give_center_to(p: int, rng: RandomNumberGenerator) -> int:
	var cards := center.duplicate()
	shuffle(cards, rng)
	piles[p].append_array(cards)
	center.clear()
	return cards.size()


func players_with_cards() -> Array[int]:
	var result: Array[int] = []
	for p in num_players:
		if count(p) > 0:
			result.append(p)
	return result


func is_over() -> bool:
	return players_with_cards().size() <= 1


# Le perdant est le dernier joueur à avoir encore des cartes.
func loser() -> int:
	var remaining := players_with_cards()
	return remaining[0] if remaining.size() == 1 else -1


# Prochain joueur (dans l'ordre des sièges) qui a encore des cartes.
func next_player_from(p: int) -> int:
	for i in range(1, num_players + 1):
		var q := (p + i) % num_players
		if count(q) > 0:
			return q
	return -1
