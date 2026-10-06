# Géométrie de la table, partagée par le serveur, les ordinateurs et l'affichage.
# Repère : centre de la table en (0, 0) ; une position sur la table est un Vector2 (x, z).

const TABLE_SIZE := 1.3
const SEAT_RADIUS := 0.55
const HAND_FORWARD := -0.14   # mains au repos : avancée vers le centre, dans le repère du siège
const HAND_RADIUS := 0.045                     # rayon de la paume
const CIRCLE_RADIUS := TABLE_SIZE / 4.0 * 0.75  # cercle rouge : 3/8 de la table en diamètre
const LINE_TOLERANCE := 0.02                    # au-delà, la main a franchi la ligne


# Angle du siège : le joueur 0 est en +z, les autres répartis régulièrement dans le sens
# des aiguilles d'une montre vu du dessus.
static func seat_angle(seat: int, players: int) -> float:
	return -seat * TAU / players


static func right_hand_rest(seat: int, players: int) -> Vector2:
	var a := seat_angle(seat, players)
	var center := Vector2(sin(a), cos(a)) * SEAT_RADIUS
	# Rotation de yaw autour de l'axe vertical : (x, z) tourne de -yaw dans le plan.
	return center + Vector2(hand_spread(players), HAND_FORWARD).rotated(-a)


# De combien la paume empiète sur le cercle (négatif : elle ne le touche pas).
static func intrusion(pos: Vector2) -> float:
	return CIRCLE_RADIUS + HAND_RADIUS - pos.length()


# Point juste à l'extérieur du cercle, dans la direction de pos.
static func outside_circle(pos: Vector2) -> Vector2:
	var direction := pos.normalized() if pos.length() > 0.001 else Vector2(0, 1)
	return direction * maxf(pos.length(), CIRCLE_RADIUS + HAND_RADIUS + 0.01)


# Écart latéral de chaque main par rapport au centre du siège : plus serré quand la
# table est pleine, pour que les mains de deux voisins ne se chevauchent pas.
static func hand_spread(players: int) -> float:
	return 0.19 if players <= 4 else (0.16 if players == 5 else 0.13)
