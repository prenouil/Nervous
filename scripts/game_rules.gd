# État pur d'une partie : tas des joueurs et tas du centre.
# Aucune notion de temps ni d'affichage ici (voir game_server.gd).

const Cards = preload("res://scripts/cards.gd")

var num_players := 4
var piles: Array = []          # piles[p] : Array[int], index 0 = carte du dessus
var center: Array[int] = []    # dernier élément = carte visible
var cards_in_play := 52       # cartes distribuées (le reste est mis de côté)


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
	# Tas égaux : s'il y a un reste (52 n'est pas divisible par 5 ou 6), ces cartes sont mises de côté.
	@warning_ignore("integer_division")
	var per_player := deck.size() / players
	cards_in_play = per_player * players
	for i in cards_in_play:
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


# Paire sur le dessus du tas.
func is_pair() -> bool:
	var n := center.size()
	return n >= 2 and Cards.forms_pair(center[n - 1], center[n - 2])


# Paire juste sous la carte du dessus (recouverte par une seule carte).
func is_covered_pair() -> bool:
	var n := center.size()
	return n >= 3 and Cards.forms_pair(center[n - 2], center[n - 3])


# Retire la carte du dessus du centre et la remet sous le tas du joueur.
func eject_top_to(p: int) -> int:
	var card: int = center.pop_back()
	piles[p].append(card)
	return card


# Le tas du centre est mélangé puis distribué une carte chacun, dans l'ordre donné,
# sous le tas des joueurs. Renvoie { joueur: nombre de cartes reçues }.
func give_center_to(players: Array[int], rng: RandomNumberGenerator) -> Dictionary:
	var cards := center.duplicate()
	shuffle(cards, rng)
	var shares := {}
	for p in players:
		shares[p] = 0
	for i in cards.size():
		var p := players[i % players.size()]
		piles[p].append(cards[i])
		shares[p] += 1
	center.clear()
	return shares


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
