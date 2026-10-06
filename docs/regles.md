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
- Le joueur actif retourne la carte du dessus de son tas, avec la main droite, et la jette au centre de la table en la retournant vers lui : **l'adversaire d'en face voit la face en premier**. Elle atterrit **face visible**, par-dessus les cartes déjà posées.
- Geste du joueur humain : pointer son tas avec la souris, **maintenir le clic gauche**, faire un petit mouvement vers le centre, **relâcher**.
- **Timer : le joueur a 5 secondes pour jouer sa carte.** S'il ne joue pas à temps, **il ramasse le tas du centre**, puis c'est au joueur suivant (choix provisoire).
- Un joueur qui n'a plus de cartes passe son tour pour retourner une carte, mais **continue de taper**.
- **Pas de temps mort** : dès qu'une carte est jouée, le joueur suivant peut jouer aussitôt.
- Une paire visible **n'arrête pas le jeu**. Elle peut être recouverte (voir « Paire recouverte »).
- La lumière de tour **suit le joueur actif avec du retard** : elle accentue le chaos de la partie.

## Paires

Deux cartes consécutives forment une paire si :
- elles ont **la même valeur** (deux dames, deux 5…) ;
- ou ce sont **deux têtes** (valet, dame, roi), par exemple valet puis roi.

## Taper sur le tas

- Geste du joueur humain : **clic droit**. La main s'abat violemment **là où elle se trouve**, n'importe où sur la table.
- Une tape **compte** seulement si elle **touche la carte du dessus** (pendant le délai de grâce : la carte du dessus de la paire ou celle qui la recouvre) **ou une main déjà posée** sur le tas.
- Une tape **à côté** est une **feinte** : sans effet ni pénalité, la main remonte et le joueur peut retaper. Elle sert à **bluffer** : les autres peuvent la prendre pour une vraie tape et taper par erreur.
- Les ordinateurs visent la carte du dessus (avec une petite imprécision) et ne feintent jamais, mais une feinte peut déclencher leur réflexe de suivre.
- **Dès qu'un joueur tape, sa main bloque le tas** : plus personne ne joue. Les autres ont **3 secondes** pour taper eux aussi. Ensuite on juge si la première tape était valide.
- Les mains s'empilent dans l'ordre d'arrivée. **L'ordre est essentiel.**
- **Verdict** : quand tout le monde a tapé (ou à la fin des 3 secondes), on annonce les perdants. Les mains se retirent **une par une** (la dernière posée d'abord) et les cartes en cause **clignotent en rouge** : les deux cartes de la paire, ou la carte tapée à tort. Ensuite seulement, le tas est distribué.
- Les cartes ramassées sont toujours **mélangées puis placées sous le tas** de ceux qui ramassent, même s'ils n'avaient plus de cartes. Quand plusieurs joueurs se partagent le tas, les cartes sont distribuées une à une.

### Tape valide

- **Le dernier à taper** ramasse toutes les cartes du centre, si tout le monde a tapé.
- Sinon, **tous ceux qui n'ont pas tapé** se partagent le tas.
- Le premier perdant, dans l'ordre des sièges à partir du joueur qui a posé la paire, **joue la carte suivante** (choix provisoire).
- Une paire visible que **personne ne tape pendant 3 secondes** : tout le monde se partage le tas.

### Paire recouverte

- Si une carte recouvre la paire, les joueurs ont **encore 0,5 seconde après son atterrissage** pour taper.
- Une tape dans ce délai **éjecte la carte qui recouvre** : on la voit voler au loin, puis elle retourne **sous le tas de son propriétaire**. La tape est valide.
- Passé ce délai, la paire est perdue : taper devient une tape par erreur.
- Une paire recouverte par deux cartes est perdue.

### Tape par erreur

- Si la première tape n'était pas valide, **seuls les tapeurs** (tous les fautifs) se partagent le tas. Ceux qui n'ont pas tapé ne sont pas sanctionnés.
- Le premier fautif joue la carte suivante (choix provisoire).

## Fin de partie

- La partie s'arrête quand **un seul joueur a encore des cartes**.
- Ce joueur est **le perdant**. Tous les autres gagnent.

## Vue et contrôles

- Caméra à la première personne, assise à la place du joueur.
- Le joueur ne voit de lui-même **que ses deux mains**.
- Des adversaires, on ne voit **que les mains et le visage**. Le corps n'est pas affiché, mais il est suggéré par la position des membres.
- **La main droite suit la souris** au-dessus de la table, et monte pour passer par-dessus le tas de la main gauche.
- **La main gauche** (qui tient le tas) se balance doucement dans un petit cercle, comme un balancier.
- **La caméra suit aussi la souris, avec une faible amplitude**, comme si le joueur regardait l'endroit qu'il pointe.

## Ordinateurs

- Temps pour jouer sa carte : **aléatoire entre 0,6 et 1,5 s**.
- **Hésitation** : si les deux cartes du dessus se ressemblent sans former une paire (valeurs proches à 2 près **et** même symbole : pique, cœur, carreau, trèfle), malus aléatoire de 0,1 à 1 s pour jouer.
- **Erreur** : dans ce même cas, chaque ordinateur (sauf celui qui vient de jouer la carte) a **1 chance sur 10** de taper par erreur. Plus il y a d'ordinateurs, plus une erreur est probable.
- Temps de réaction pour taper : **aléatoire** à chaque paire, de 0,25 à 0,8 s après l'arrivée de la carte.
- Celui qui a joué la carte la voit mal : **malus de réaction de 0,2 à 0,5 s**.
- **Réflexe** : quand quelqu'un tape alors que l'ordinateur ne voit pas de paire, il a **10 % de chances** de suivre, retirées **à chaque nouvelle tape** (plus il y a de tapeurs, plus il est tenté). 20 % pour celui qui a joué la carte, qui l'a mal vue.
- Comportement à affiner plus tard.

## Direction artistique

- Style envisagé : **cartoon** (à confirmer).
- Prototype : formes simples (blocs pour les mains, sphères pour les visages), pour régler les mouvements et les règles avant l'habillage.
- Ensuite : modèles 3D gratuits ou fournis.

## Technique

- Moteur : **Godot 4** (GDScript).
- Le multijoueur en ligne est prévu dès le départ. Les règles et l'ordre des tapes seront décidés par une seule autorité (le serveur, ou l'hôte), pour rester justes malgré la latence.
