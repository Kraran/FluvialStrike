# Fluvial Strike — fiche de référence du gameplay

## Version de travail

**River Raid d’Activision, Atari 2600, partie solo, difficulté B.** La capture locale affiche « Played By RickyC » et correspond au longplay Atari 2600 de World of Longplays. Dans la description, RickyC indique avoir choisi le tir dont la trajectoire peut suivre le déplacement du jet. Le manuel attribue ce comportement au réglage B. La ROM locale européenne reproduit le départ, le premier pont et le premier îlot. La révision exacte utilisée par RickyC reste indéterminée. [Longplay de RickyC](https://www.youtube.com/watch?v=gombHp5wMrk) · [Manuel Atari 2600](https://www.atariage.com/manual_html_page.php?SoftwareLabelID=409)

| Source | Ce qu’elle établit |
| --- | --- |
| **Vidéo** | Ordre des événements du longplay, géométrie affichée, cadrage, positions apparentes et variations visibles de score. |
| **Manuel** | Commandes, barème, conditions générales de collision, carburant, vies et reprises. |
| **Émulation contrôlée** | Mesures par image sur la ROM locale. Résultats consignés sous le protocole d’essais. |

`RiverRaid.mp4` dure 1 453,27 s. Le flux est en 548 × 360 à environ 24,93 images/s. Cette cadence décrit l’enregistrement. SHA-256 de la vidéo : `9685287CD7EA3578477CD51352C79B40D701348C6D5E3F41D392EA8086D225FA`.

## Relevé du départ au premier îlot

Les temps se rapportent au fichier local. Les repères sont des observations à des instants échantillonnés. Autour du pont, le pas de lecture est de 0,125 s. Les points décimaux du tableau facilitent le report dans des scripts.

| Temps dans la vidéo | Observation | Score visible |
| --- | --- | ---: |
| 00:03–00:10 | Séquence d’introduction avec le crédit du joueur. | — |
| 00:11–00:13 | Remise en place au départ, puis jet actif. Le premier tanker est détruit avant l’image relevée à 00:13. | 30 à 00:13 |
| 00:14–00:18 | Long chenal droit. Hélicoptère et dépôts en alternance, avec des gains successifs de 80 points après le premier relevé. | 90 à 410 |
| 00:28.875 → 00:29.125 | Le chenal se resserre. Le tablier du premier pont entre par le haut. | 1 100 |
| 00:29.500 → 00:30.000 | Le jet et un dépôt se superposent visuellement. Cas à rejouer pour mesurer le transfert de carburant. | 1 100 |
| 00:30.125 → 00:30.250 | Tablier encore intact. | 1 160 |
| 00:30.375 | Premier échantillon avec le tablier détruit, un flash coloré et **+500**. | 1 660 |
| 00:32 environ | Le jet franchit l’axe du pont détruit. Les accès routiers restent visibles sur les rives. | 1 690 |
| 00:36 environ | Nouveau recouvrement du jet et d’un dépôt, dans la section qui suit le pont. | 1 810 |
| 00:37 → 00:43 | Premier îlot fin. Le jet est à droite de l’axe central à 00:38 et à gauche à 00:40–00:42. L’îlot sort par le bas vers 00:43. | 1 890 à 2 220 |

### Dimensions visibles

Coordonnées dans l’image source, origine en haut à gauche. Les intervalles horizontaux incluent leur première borne et excluent leur dernière. Les bords ont été relevés par seuil de couleur dans l’eau. Le cadrage et les silhouettes sont exploitables pour le prototype. Les limites de collision devront être mesurées séparément.

| Repère | Échantillon | Mesure |
| --- | --- | --- |
| Aire de jeu | Ligne noire de séparation à `y=290` | **548 × 290 px** au-dessus du HUD, soit un rapport d’environ **1,89:1**. |
| Ligne du jet | Silhouette à 00:14, 00:28, 00:38 et 00:41 | Environ `y=258–281`, centre à **93 %** de la hauteur de l’aire de jeu depuis le haut. |
| Premier chenal large | 00:15, ligne `y=20` | `x=[130,390[`, soit **260 px** ou **47,4 %** de la largeur. |
| Passage du premier pont | 00:30, lignes `y=100` et `y=180` | `x≈[202,318[`, soit **116 px** ou **21,2 %** de la largeur. |
| Premier îlot fin | 00:40, ligne `y=100` | Eau à gauche `x=[30,230[`, îlot `x=[230,288[`, eau à droite `x=[288,490[`. L’îlot fait **58 px**, environ **10,6 %** de la largeur. |

Pour le prototype, rapporter les abscisses à 548 et les ordonnées à 290. Le chenal large et le passage du pont sont centrés vers **47,4 %** de la largeur dans la capture. Conserver cet axe tant que la comparaison avec la sortie native de l’émulateur ne justifie pas de corriger le cadrage.

## Règles du manuel et paramètres à tester

| Système | Règle de référence | Points de contrôle dans l’émulateur |
| --- | --- | --- |
| Déplacement | Gauche et droite déplacent le jet. Haut et bas accélèrent ou ralentissent le défilement. | Déplacement latéral par image, délai au premier appui, comportement au relâchement et à l’inversion. Vitesses min., neutre et max., rampes et effet des diagonales. |
| Tir | Appui simple ou maintenu. En B, le joueur peut diriger le projectile après le départ. En A, il continue tout droit. | Position d’émission, délai avant répétition, limite de projectiles actifs, vitesse relative à la caméra, disparition hors champ et relation entre la position du jet et celle du projectile. |
| Carburant | Débit de consommation constant quelle que soit la vitesse selon le manuel. Alerte sous un quart de réservoir. Le survol d’un dépôt ravitaille, avec un gain supérieur si le jet passe plus de temps au-dessus. | Jauge au départ et après reprise, débit par image, bornes de recouvrement, gain, seuil exact de l’alerte, comportement à réservoir plein ou vide et ordre des événements si le dépôt est détruit pendant le survol. |
| Collisions | Contact létal avec une berge ou un ennemi. Le survol d’un dépôt est autorisé. | Limites effectives sur une berge droite, une transition et un îlot. Contact avec le tablier intact, les accès et les ennemis. Priorité quand un tir et un contact surviennent sur la même image. |
| Ennemis et progression | Tankers, hélicoptères, jets et dépôts se succèdent le long de sections terminées par un pont. | Déclenchement, direction et vitesse de chaque cible. Positions et séquence après reset et après reprise. |
| Score et réserves | Tanker **30**, hélicoptère **60**, dépôt **80**, jet **100**, pont **500**. Trois jets de réserve annoncés au départ et un renfort tous les **10 000** points. | Vérifier le compteur affiché au départ et à la première perte, ainsi que le plafonnement effectif. |
| Reprise | Avec une réserve, retour au début de la section. Si son pont a déjà été détruit, reprise à la section suivante. | Vérifier une mort avant la destruction du pont, puis après la destruction mais avant le franchissement. Relever le délai, le point de réapparition, le score et l’état du carburant. |

[Manuel Activision de River Raid sur Atari 2600](https://www.atariage.com/manual_html_page.php?SoftwareLabelID=409)

## Protocole d’essais contrôlés

1. **Identifier la copie.** Relever le nom et le SHA-256 du fichier du jeu extrait, la version de l’émulateur, le format vidéo détecté et les réglages des deux commutateurs de difficulté. Démarrer en solo avec le joueur 1 en B. Comparer le début de rivière, les premières cibles et le comportement du missile avec le longplay.
2. **Fixer l’état initial.** Dans Stella, partir d’un état enregistré au premier instant pilotable. Pour les cas près du pont et d’un dépôt, conserver un état avant l’approche et la séquence de commandes utilisée pour l’atteindre. Vérifier chaque scénario sur deux exécutions depuis le même état.
3. **Avancer image par image.** Le débogueur de Stella expose `frame` et les commandes `joy0Up`, `joy0Down`, `joy0Left`, `joy0Right` et `joy0Fire`. Avec le jet en vol et les autres commandes relâchées, un premier essai peut enchaîner `joy0Left 1`, `frame #12`, `joy0Left 0`, puis `frame #12`. Relever chaque transition et le mouvement aux images intermédiaires. [Documentation du débogueur Stella](https://stella-emu.github.io/docs/debugger.html)
4. **Enregistrer des observations comparables.** Pour chaque essai, conserver l’état initial, les commandes indexées par image, la position du jet et du projectile, le déplacement d’un repère fixe du décor, l’état de la jauge, le score, les réserves et les événements. Mesurer le cadrage dans l’image native et garder les captures aux transitions importantes.

| Essai | Séquence minimale | Résultat à relever |
| --- | --- | --- |
| P01 · Déplacement latéral | Neutre, gauche, neutre, droite, inversion immédiate. | Première et dernière images de mouvement. Déplacement latéral par image et éventuelle inertie. |
| P02 · Vitesse | Depuis le même état, comparer neutre, haut maintenu et bas maintenu. | Déplacement vertical d’un repère fixe, changement de vitesse et consommation sur le même nombre d’images. |
| P03 · Tir | Appui bref puis maintien. Tir suivi d’un déplacement, en B puis en A. | Nombre de tirs, trajectoires, durée de vie et première image d’impact. |
| P04 · Dépôt | Même approche à deux vitesses, puis tir pendant le survol. | Début et fin du transfert, gain, score et ordre des événements. |
| P05 · Berge et îlot | Déplacer la trajectoire par pas d’un pixel logique autour d’un passage limite. | Dernière trajectoire sûre et première trajectoire létale. |
| P06 · Pont et reprise | Heurter le pont intact. Le détruire lors d’un autre essai, puis perdre le jet avant de le franchir. | +500 une seule fois à la destruction, état du tablier, section et délai de reprise. |
| P07 · Fin et renforts | Laisser la jauge se vider puis épuiser les réserves. Tester séparément le franchissement du premier seuil de 10 000. | Alerte, mort, fin de partie, compteur de réserves et attribution du renfort. |
| P08 · Séquence complète | Rejouer du départ au premier îlot avec les commandes enregistrées. | Ordre des cibles, points de passage, score et état final identiques entre deux exécutions. |

### Critères de fidélité à valider

- **Score, ordre des événements, réserves et section de reprise** concordent exactement pour un même rejeu.
- **Position et temps de passage** concordent à un pixel logique et une image native près comme cible provisoire. Pour un contact limite, les deux trajectoires de contrôle doivent donner le même verdict que la référence.
- **Carburant** comparé sur la valeur interne si elle est identifiée. Sinon, relever les transitions de jauge et d’alerte à l’image native. La précision retenue dépendra de ce que les essais permettent de mesurer.
- **Décor HD** évalué avec le même rejeu et le même cadre jouable. L’habillage conserve les résultats du prototype.

## Mesures sur la copie locale

ROM fournie : `River Raid (Europe).a26`, 4 096 octets. Le MD5 `6ce2110ac5dd89ab398d9452891752ab` correspond à l’entrée européenne du catalogue Libretro. SHA-256 : `4081DBAE4A2F78ABB77BD840453E10D9034DE72A345B009141DAC6B220FE2166`. Les essais ont chargé directement le cœur Libretro Stella `8.0_pre 6efad98` de RetroBat, avec le format vidéo sur auto. Le cœur a annoncé **60 images/s** et a livré des images de **160 × 228**. Les 60 images/s sont la cadence de la configuration testée. La cadence et la révision exactes du longplay restent à confirmer. [Catalogue Libretro](https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/no-intro/Atari%20-%202600.dat) · [Options du cœur Stella](https://docs.libretro.com/library/stella/)

La zone visible de la capture correspond au cœur Stella après retrait des marges. Dans une image Stella au départ, la largeur visible va de `x=8` à `x=159`, l’axe du chenal est à `x=80` et les largeurs des passages large et étroit sont respectivement **72** et **32** pixels natifs. Les rapports **72/152** et **32/152** concordent avec les **47,4 %** et **21,2 %** mesurés dans le MP4. Le champ au-dessus du HUD fait environ **161 lignes** dans Stella.

Les essais injectent les entrées RetroPad et lisent la RAM en fin d’image. Les noms des variables ont été rapprochés du désassemblage annoté de la version Atari 2600. Les valeurs ci-dessous proviennent de l’exécution de la ROM locale. [Désassemblage annoté, carte des variables](https://github.com/johnidm/asm-atari-2600/blob/master/riverraid.asm)

| Essai | Résultat mesuré |
| --- | --- |
| **P01 · Déplacement** | Depuis `x=76`, le premier appui donne `75` à gauche ou `77` à droite. En maintien, le prochain pixel est franchi à l’image 8, puis le suivant à l’image 11. À 12 images, le déplacement est de 3 px dans chaque sens. Au relâchement à l’image 13, la position ne change pas. Une inversion immédiate après 12 images donne `x=74` en passant de gauche à droite et `x=79` en passant de droite à gauche. |
| **P02 · Vitesse** | Après stabilisation, le décor parcourt **8, 16 ou 32 lignes natives en 16 images** selon que bas est maintenu, que l’axe est neutre ou que haut est maintenu. La variable interne de vitesse se stabilise à **64 / 128 / 254**. Haut la fait monter par pas de 2 par image dans l’essai. Sur les 100 premières images, la jauge baisse de **3 200 unités** dans les trois cas. |
| **P03 · Tir** | Dans l’essai d’un tir puis d’un déplacement d’un pixel à droite, la coordonnée du missile reste à `81` en A. Elle passe de `81` à `82` en B. Dans les deux cas, sa progression verticale mesurée est de **6 unités natives par image** jusqu’à l’impact de cet essai. En maintenant tir, les émissions observées depuis l’état initial ont lieu aux images **11, 37, 63, 89, 115 et 141**, avec un intervalle de **26 images** sur cette séquence. |
| **P04 · Dépôt** | Sur le même dépôt, à abscisse constante, **20 images de gain** à vitesse minimale, **11** au neutre et **8** à vitesse maximale. Le gain net par image de transfert est de **480 unités** avant saturation. Le premier jet pilotable démarre à **65 503 unités** et perd **32** unités par image de vol sans ravitaillement. |
| **P05 · Berge** | Dans le chenal de départ, maintenir droite laisse le jet en vol à l’image **29**, à `x=90`. À l’image **30**, le crash est enregistré à la même abscisse. Ce couple d’images sert de contrôle pour l’ordre entre déplacement, défilement et détection de collision. |
| **P06 · Pont et reprise** | Tir et haut maintenus depuis le départ, le premier pont explose à l’image **487** et rapporte **500 points**. En ajoutant ensuite droite et en relâchant le tir, un crash à l’image **527** provoque la reprise en section **2** à l’image **703**, avec **650 points**. En coupant le tir dès l’image **435** dans un essai distinct, le pont reste intact et une collision avec le tanker à l’image **529** ramène le jet à la section **1** à l’image **705**, avec **150 points**. En coupant le tir après l’image **450**, le crash au tablier et les **+500** coïncident à l’image **542**. La reprise a lieu en section **2** à l’image **718** avec **650 points**. Le délai de reprise est de **176 images** dans les trois cas. |
| **P07 · Vies et carburant** | Le HUD affiche 3 au départ. En maintenant droite, trois reprises restent possibles et le quatrième crash mène à la fin de partie. Dans des essais isolés préparés en RAM, **31 unités** de carburant déclenchent la panne à l’image suivante et un tanker détruit à **9 970 points** ajoute une réserve au passage à **10 000**. Un relevé audio sur 45 images confirme le changement de signal en passant sous **16 384 unités**, soit le seuil du quart de réservoir. |
| **P08 · Rejeu de bout en bout** | Deux rejeux de **809 images** depuis le même état traversent le premier pont et contournent le premier îlot par la gauche. Ils terminent en vol, section 2, à `x=56`, avec **930 points**, **3 réserves** et **50 847 unités** de carburant. La RAM et l’image finale sont identiques dans les deux exécutions. |

### Rejouer le segment de référence

L’état initial des essais est obtenu sur un démarrage à froid en laissant passer **60 images**, en appliquant **Reset** et les deux commutateurs **B** pendant une image, puis en laissant passer **45 images sans entrée**. Maintenir ensuite le tir jusqu’à la première image où le jet est pilotable. L’état attendu à cet instant est `x=76`, section **1**, score **0**, **3 réserves**, vitesse interne **66** et carburant **65 503**. L’image **1** du tableau commence à l’entrée suivante.

| Images incluses | Commandes maintenues |
| --- | --- |
| 1 à 550 | Haut + Tir |
| 551 à 585 | Haut + Tir + Gauche |
| 586 à 809 | Haut + Tir |

Cet itinéraire reproductible sert de référence pour le prototype. Les commandes originales du longplay restent inconnues. Les essais complémentaires concernent les limites de collision sur les deux bords de l’îlot, la cadence du tir dans d’autres configurations d’impact, le dépôt touché en cours de ravitaillement et les trajectoires et apparitions au-delà du premier segment.
