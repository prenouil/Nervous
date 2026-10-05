# Nervous — Règles et conception

Document de référence du jeu. Les points marqués **[À DÉFINIR]** sont encore ouverts.

## Concept

Jeu de cartes de table en 3D, vu à la première personne. Jeu de rapidité inspiré de la bataille « où l'on tape sur le tas », avec un jeu classique de 52 cartes.

- 4 joueurs autour d'une table.
- Pour l'instant : 1 joueur humain contre 3 ordinateurs.
- À terme : **multijoueur en ligne**.

## Mise en place

- Les 52 cartes sont mélangées et distribuées équitablement : avec 4 joueurs, chacun reçoit un tas de 13 cartes.
- Chaque joueur tient son tas **dans la main gauche, face cachée**.

## Déroulement d'un tour

- Les joueurs jouent **chacun leur tour**.
- Une **lumière qui se déplace au-dessus des joueurs** indique à qui c'est le tour.
- Le joueur actif retourne la carte du dessus de son tas, avec la main droite, et la jette au centre de la table. Elle atterrit **face visible**, par-dessus les cartes déjà posées.
- Geste du joueur humain : pointer son tas avec la souris, **maintenir le clic gauche**, faire un petit mouvement vers le centre, **relâcher**.
- **Timer : le joueur a 5 secondes pour jouer sa carte.** S'il ne joue pas à temps, **il ramasse le tas du centre**, puis c'est au joueur suivant (choix provisoire).
- Un joueur qui n'a plus de cartes passe son tour pour retourner une carte, mais **continue de taper**.

## Taper sur le tas

- Quand **deux cartes consécutives ont la même valeur** (deux dames, deux 5…), tous les joueurs doivent taper sur le tas.
- Geste du joueur humain : placer le curseur sur le tas du milieu et faire un **clic droit**. Le bras s'avance et la main s'abat violemment sur le tas.
- Les mains s'empilent dans l'ordre d'arrivée. **L'ordre est essentiel.**
- **Le dernier à taper** ramasse toutes les cartes du centre. Elles sont **mélangées puis placées sous son tas**, même s'il n'avait plus de cartes.
- **Le perdant joue la carte suivante.**

## Taper par erreur

Règle essentielle du jeu, qui couvre plusieurs cas : **[À DÉFINIR]**.

## Fin de partie

- La partie s'arrête quand **un seul joueur a encore des cartes**.
- Ce joueur est **le perdant**. Tous les autres gagnent.

## Vue et contrôles

- Caméra à la première personne, assise à la place du joueur.
- Le joueur ne voit de lui-même **que ses deux mains**.
- Des adversaires, on ne voit **que les mains et le visage**. Le corps n'est pas affiché, mais il est suggéré par la position des membres.
- **La main droite suit le curseur de la souris** au-dessus de la table.
- **La caméra suit aussi la souris, avec une faible amplitude**, comme si le joueur regardait l'endroit qu'il pointe.

## Ordinateurs

- Chacun a son propre temps de réaction (rapide, moyen, lent), avec une part de hasard.
- Ils peuvent faire des erreurs, par exemple taper sans raison.
- Comportement à affiner plus tard.

## Direction artistique

- Style envisagé : **cartoon** (à confirmer).
- Prototype : formes simples (blocs pour les mains, sphères pour les visages), pour régler les mouvements et les règles avant l'habillage.
- Ensuite : modèles 3D gratuits ou fournis.

## Technique

- Moteur : **Godot 4** (GDScript).
- Le multijoueur en ligne est prévu dès le départ. Les règles et l'ordre des tapes seront décidés par une seule autorité (le serveur, ou l'hôte), pour rester justes malgré la latence.
