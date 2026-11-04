# 60 — UI / UX (domaine ui)

Domaine : `client/Controllers/UI/*`, `server/Services/PingService.luau`, `shared/Config/UI.luau`.
Contrat : `docs/ARCHITECTURE.md` (sections 2, 6, 7). Vision : `00-vision.md` sections 1, 5.2, 10, 11.3, 13.

Objectif : un écran lisible au milieu de 200 ennemis sur un téléphone de 6 pouces, pour des joueurs de 9 à 15 ans, conçu mobile d'abord. HUD réduit aux coins, cartes en bas, couleurs de rareté reconnaissables sans lire **et** sans voir les couleurs (toujours un 2e canal).

---

## 1. Principes

| Règle | Valeur | Source |
| --- | --- | --- |
| Texte affiché minimum | 12 px (après échelle) | Responsive UI, AI Pitfalls - UI and Input |
| Cible tactile minimum | 44 px (boutons de combat 64–84 px) | Responsive UI, Mobile Button Layout Editor |
| Écart minimum entre cibles | 8 px | Responsive UI |
| Chevauchements | 0, vérifiés aux 5 vues (844×390, 667×375, 1024×768, 1920×1080, téléphone à encoche) | HUD Design |
| Zones sûres | chaque `ScreenGui` règle `ScreenInsets` explicitement ; HUD interactif en `CoreUISafeInsets`, fonds plein écran en `None` | Safe Areas and Insets |
| `SafeAreaCompatibility` | `None` sur toutes nos guis | Safe Areas and Insets |
| `ResetOnSpawn` | `false` partout | ScreenGui Fundamentals (SYMPTOMS) |
| `DisplayOrder` | explicite et unique par gui (tableau §2) | SYMPTOMS : popup sous le HUD |
| Polices | `FontFace` uniquement : Builder Sans (corps), Fredoka One (titres/chiffres). Jamais Gotham (retiré, rend Montserrat) | Text Fonts and Rich Text |
| Taille du texte | `TextSize` fixe + `AutomaticSize` ; jamais `TextScaled` (ignore `PreferredTextSize`) | Accessibility |
| Contour du texte | `UIStroke` ≤ 7 % de la taille (sinon « 10 » devient « 1 » + tache) | SYMPTOMS / UIStroke on Text |
| Animation « pop » | on anime un `UIScale`, jamais `Size` ni `UIStroke.Thickness` | SYMPTOMS / UI Motion |
| Boutons | `Activated` pour les clics ; `InputBegan/InputEnded` seulement pour les boutons maintenus (Saut = plané) | Input - UIS and CAS |

### 1.1 Profil d'appareil et échelle

Classement par capacité, pas par devinette (Responsive UI, section 1) :

- **téléphone** = `TouchEnabled` et petit côté de la vue < 520 px ;
- **tablette** = `TouchEnabled` et petit côté ≥ 520 px ;
- **PC / console** = le reste (`PreferredInput` choisit les indications de touches).

Les tailles de ce document sont en **pixels logiques à l'échelle 1** (référence : téléphone 844×390). Chaque zone d'écran a son propre `UIScale` (jamais imbriqué : double réduction, AI Pitfalls) : échelle = clamp(petit côté / 420, 1, 1,4). Téléphone = 1 (plancher : pas de texte à 6 px), tablette 768 → 1,4 plafonné (1024 px de large = 731 px logiques, assez pour les zones du haut : 220 + 300 + 140), PC 1080 → 1,4. Recalculé quand `ViewportSize` change.

### 1.2 Thème : module de code plutôt que `StyleSheet`

Le vault (UI Design Systems §4) décrit le style moteur (`StyleSheet` / `StyleRule` / `StyleLink`, jetons `$Nom`, `StyleQuery`) mais note que l'éditeur est en bêta (oct. 2026) et que la syntaxe des sélecteurs est « la partie la plus sensible aux versions ». Toute notre UI est **construite par code** : un module de thème (`UITheme`) est la source unique des jetons (couleurs par rôle, typo, espacements, rayons, contours, mouvement). Aucun écran ne code une couleur en dur. Migration possible vers `StyleSheet` plus tard : les jetons ont déjà des noms de rôle.

---

## 2. Écrans et `ScreenGui`

| Gui | Module | DisplayOrder | ScreenInsets | Visible quand |
| --- | --- | --- | --- | --- |
| `COHUE_HUD` | HUD | 10 | CoreUISafeInsets | phase Running / Boss / BossDefeated / FinalWave |
| `COHUE_Minimap` | Minimap | 11 | CoreUISafeInsets | idem (gui séparée : elle bouge à 10 Hz) |
| `COHUE_PingWorld` | PingUI | 12 | None (non interactif, espace de la vue) | toujours en run (flèches de bord) |
| `COHUE_SettingsGear` | SettingsUI | 13 | CoreUISafeInsets | en run (sous la mini-carte) |
| `COHUE_Mobile` | MobileButtons | 15 | CoreUISafeInsets | en run |
| `COHUE_Vignette` | HUD | 24 | None (décor) | à terre |
| `COHUE_Downed` | HUD | 25 | CoreUISafeInsets | à terre / fantôme |
| `COHUE_Cards` | CardUI | 20 | CoreUISafeInsets | offre ouverte |
| `COHUE_Shrine` | ShrineUI | 21 | CoreUISafeInsets | offre d'autel ouverte |
| `COHUE_Announce` | HUD | 30 | CoreUISafeInsets | annonce en cours |
| `COHUE_PingWheel` | PingUI | 35 | CoreUISafeInsets | roue ouverte |
| `COHUE_Loadout` | LoadoutUI | 40 | DeviceSafeInsets (+ fond `None`) | phase Loadout |
| `COHUE_End` | EndScreen | 50 | DeviceSafeInsets | `RunSummary` reçu |
| `COHUE_Settings` | SettingsUI | 60 | CoreUISafeInsets | bouton engrenage |

Sur téléphone, un panneau plein écran (Loadout, Fin, Réglages) **masque le HUD** au lieu de le recouvrir (Responsive UI §6 : « hide, do not shrink »).

---

## 3. HUD en run

### 3.1 Positions par appareil (pixels logiques, avant `UIScale`)

| Élément | Téléphone | Tablette | PC |
| --- | --- | --- | --- |
| Vitaux (PV, bouclier, niveau, XP, pièces) | haut gauche, 210×60 | haut gauche | haut gauche |
| Armes + Grimoires | haut gauche sous les vitaux (icônes 28 / 22 px) — le bas gauche est le joystick | bas gauche (36 / 28 px) | bas gauche (36 / 28 px) |
| Équipe (≤ 3 coéquipiers) | gauche, sous le build, lignes 150×22 | sous les vitaux | sous les vitaux |
| Chrono + monde/stage | haut centre, 120×36 | haut centre | haut centre |
| Flèche du boss | sous le chrono, 36 px + distance | idem | idem |
| Barre de boss | sous le chrono, 280×14 + nom | 280 | 280 |
| Annonces (sous-titres) | haut centre, y = 96, largeur ≤ 520 | idem | idem |
| Mini-carte | haut droite, 112 px | 140 px | 160 px |
| Engrenage Réglages | sous la mini-carte, 44×44 | idem | idem |
| Boutons tactiles | bas droite (§8) | bas droite | — |
| Jauge d'Ultime | sur le bouton Ultime | sur le bouton | bas droite, 140×36, indication « E » / « Y » |
| Cartes | bas centre (§4) | bas centre | bas centre |
| Fil des pings | gauche, sous l'équipe, 3 lignes max | idem | idem |

Toutes les zones du haut commencent sous la barre Roblox grâce à `CoreUISafeInsets` (jamais de hauteur de barre codée en dur : Safe Areas §5).

### 3.2 Vitaux (haut gauche)

- **Barre de PV** 200×16, rouge corail `#F0564A`, texte « 85 / 100 » dessus (2e canal : le nombre). Fond sombre `#1C2230` à 25 % de transparence × `PreferredTransparency`.
- **Bouclier** : barre cyan `#5AD2FF` superposée sur le haut de la barre de PV (6 px), largeur = bouclier / PV max.
- **Niveau** : pastille ronde 32 px « 12 » (Fredoka One 18), libellé « Nv » / « Lv ».
- **XP** : barre 200×6 violet clair `#B68CFF` sous la barre de PV.
- **Pièces** : « ● 1 240 » jaune `#FFD447`, 14 px.
- Données : `PlayerVitals` (forme perso), `PlayerProgress`, `Coins`. Écriture seulement si la valeur change.

### 3.3 Chrono (haut centre)

- « 9:42 » Fredoka One 28, blanc. Sous 1:00 : **rouge `#FF4A3D` et 40 px** ; pas de clignotement (réduction des flashs) — un seul « pop » à 1:00 si le mouvement n'est pas réduit.
- Ligne 12 px dessous : « Bois Grognon · Tier 1 · Stage 2 » (noms du monde via Config.Worlds si présent, sinon id).
- Vague Finale : le chrono devient « VAGUE FINALE 1:23 » (secondes survécues, `finalWaveSeconds`), orange.
- Interpolation locale entre deux `RunState` (envoyé chaque seconde) ; texte réécrit seulement quand la seconde affichée change, boucle à 4 Hz (Race HUD : pas de texte par image).

### 3.4 Flèche du boss et barre de boss

- **Flèche** : dès `RunState.bossRevealed` et `bossPosition`. Triangle rouge 36 px sous le chrono, tourné vers le boss par rapport à la caméra (cap horizontal), + « 120 m ». Mise à jour à chaque image **seulement** tant que la flèche est visible (connexion créée/coupée).
- **Barre de boss** : quand `BossState` arrive (et pendant 3 s après la dernière trame). Nom localisé (`name`), barre 280×14 rouge sombre `#C8323C` + texte « 64 % », pastilles de phase (1 par phase). Masquée à la victoire (`BossDefeated`).

### 3.5 Équipe, mise à terre et relève

- **Liste d'équipe** (forme `{ team = … }` de `PlayerVitals`) : nom d'affichage (`AutoLocalize = false`), mini barre 90×6, et un état écrit : « À TERRE » orange avec icône « + », « FANTÔME » gris. Jamais seulement une couleur.
- **Moi à terre** : vignette de bord rouge (gui `None`, 60 % transparente, fixe si flashs réduits, respiration lente sinon), panneau central « À TERRE — 18 s » / « DOWNED — 18 s », barre de relève (`reviveProgress`) verte-bleue, et « Un coéquipier doit rester 3 s près de toi ».
- **Fantôme** : « FANTÔME — tu peux encore charger les autels (25 %) ». Pas de vignette.
- Coéquipier à terre : sa marque sur la mini-carte devient une croix « + » et le fil de pings affiche « Alex est à terre ! ».

### 3.6 Build (armes et Grimoires)

- Ligne d'armes : `weaponSlots` cases (vides = contour pointillé, 40 % opaques). Icône = carré arrondi coloré + 2 lettres (pas d'id d'asset), badge de niveau en bas à droite.
- Ligne de Grimoires : `grimoireSlots` cases plus petites.
- Données : `Build`. Noms via Config.Weapons / Config.Grimoires (si absents : id).

### 3.7 Compagnon

Nom du stade (`CompanionState.name`) + « Nv 5 » au-dessus du build ; « sonné » en gris si `stunned`. Jauge d'Ultime : §8.

### 3.8 Annonces avec sous-titres

`Announce { kind, text, duration }` → bannière haut centre, Fredoka One 22, fond sombre arrondi. File d'attente, **une à la fois** (HUD Design §3). Les annonces sont les sous-titres des annonces sonores (vagues, boss, Vague Finale) : elles restent `duration` s (min 2 s, max 6 s).

| kind (run) | Accent | Icône |
| --- | --- | --- |
| `Boss`, `BossRevealed`, `FinalWave` | rouge | « ! » |
| `Stage`, `Portal` | bleu | « » » |
| autre | blanc | aucune |

Entrée : pop d'échelle 0,9 → 1 en 0,15 s ; mouvement réduit : fondu seul.

---

## 4. Cartes de niveau (sans pause, 8 s)

`CardOffer { offerId, cards, expiresIn, banish, skip, reroll }` ; `{ offerId, closed = true }` ferme.

### 4.1 Disposition

- 3 cartes en bas centre. Téléphone : 132×112, écart 8, marge basse 8 (entre le joystick et les boutons d'action) ; tablette / PC : même taille × échelle.
- Chaque carte : bordure de rareté (contour 2 / 3 / 4 / 4 px selon la rareté), **losanges de rareté** (1 à 4) en haut à gauche, icône ronde 36 px (2 lettres), titre 1 ligne (14 px gras), description 1 ligne (12 px), « NOUVEAU » / « NEW » ou « Nv 3 », étiquette « Compagnon » si la carte vient du compagnon, indication de touche « 1 / 2 / 3 » sur clavier.
- Au-dessus, rangée de 3 boutons 44 px : **Relancer (n)**, **Passer (n)**, **Bannir (n)** (grisés à 0), puis **l'anneau de 8 s** (40 px).

### 4.2 Anneau de 8 s

Disque qui se vide dans le sens horaire depuis midi (2 demi-disques découpés + `UIGradient` à marche nette, rotation mise à jour à chaque image pendant l'offre seulement), chiffre des secondes restantes au centre (réécrit 1 fois par seconde). Sous 3 s : anneau orange. À 0 le serveur choisit (la plus rare) et envoie `closed`.

### 4.3 Actions

| Action | Geste | Remote |
| --- | --- | --- |
| Choisir | toucher la carte / touche 1–3 (actions `Card1`–`Card3`) / clic | `CardChoice(offerId, "pick", i)` |
| Relancer | bouton | `CardChoice(offerId, "reroll")` |
| Passer | bouton | `CardChoice(offerId, "skip")` |
| Bannir | bouton → mode bannir (cartes barrées d'un « × », bandeau « Touchez une carte à bannir ») → toucher la carte | `CardChoice(offerId, "ban", i)` |

Après un envoi, les cartes sont verrouillées jusqu'à la réponse du serveur (nouvelle offre ou `closed`) : pas de double envoi. Une nouvelle offre remplace l'ancienne.

### 4.4 Couleurs de rareté

| Rareté | Défaut | Daltonien (Okabe-Ito, échelle de luminosité) | 2e canal |
| --- | --- | --- | --- |
| Common / Commun | gris `#AAB0BA` | blanc cassé `#E6E6E6` | 1 losange, contour 2 px |
| Rare / Rare | bleu `#3C96FF` | bleu ciel `#56B4E9` | 2 losanges, contour 3 px |
| Epic / Épique | violet `#B45AFF` | vermillon `#D55E00` | 3 losanges, contour 4 px |
| Legendary / Légendaire | or `#FFBE28` | jaune `#F0E442` | 4 losanges, contour 4 px + fond doré léger |

Le mode daltonien **change de palette**, pas de filtre (`ColorCorrectionEffect` ne peut pas déplacer les teintes : Colour-Blind Safe Design §4.1). Les formes ne changent jamais d'un mode à l'autre.

---

## 5. Autels

- `ShrineOffer { offerId, choices = {{ stat, value, rarity }} }` → panneau au-dessus des cartes (ou à leur place s'il n'y a pas d'offre de carte) : 3 boutons 120×64, « +12 % Dégâts » / « +12% Damage », bordure + losanges de rareté. `ShrineChoice(offerId, i)`. Pas de minuterie côté client : le serveur ferme.
- Charge : depuis `ShrineState`, pastille « Autel 45 % · 2 joueurs » au-dessus du centre bas quand un autel `Charging` est à moins de 14 studs.

---

## 6. Mini-carte

- Radar rond, **nord en haut** (monde −Z vers le haut, Minimap note §1), centré sur le joueur, rayon couvert 120 studs. Pas d'image de carte (aucun id d'asset) : fond sombre rond + anneau.
- Mise à jour à 10 Hz (pas par image), marques en pool.
- Les marques hors du rayon sont collées au bord (sauf autels).

| Marque | Couleur défaut | Daltonien | Forme (2e canal) | Source |
| --- | --- | --- | --- | --- |
| Moi | blanc | blanc | flèche orientée | personnage local |
| Coéquipier | vert `#4CD964` | vert-bleu `#009E73` | chevron orienté ; croix « + » si à terre | personnages + `PlayerVitals.team` |
| Autel | bleu `#3C8CFF` | bleu `#0072B2` | losange (plein si prêt, creux si utilisé) | `ShrineState` |
| Coffre | jaune `#FFD447` | jaune `#F0E442` | carré | `LootRenderer.getChests()` (demande de contrat) |
| Boss | rouge `#FF3B30` | vermillon `#D55E00` | grand rond « ! » | `RunState.bossPosition` / `BossState.position` |
| Ping | couleur du ping | idem | anneau 1 s puis point | `PingBroadcast` |

Légende : petit bouton « ? » dans Réglages → ce tableau en texte.

Appui long 0,5 s sur la mini-carte (tactile) → roue de pings à l'endroit touché (§7).

---

## 7. Pings (6)

| id | FR | EN | Couleur | Glyphe | Durée |
| --- | --- | --- | --- | --- | --- |
| `Boss` | Boss ici ! | Boss here! | rouge | `!` | 8 s |
| `Shrine` | Autel | Shrine | bleu | `*` | 6 s |
| `Help` | À l'aide ! | Help! | orange | `+` | 6 s |
| `Chest` | Coffre | Chest | jaune | `#` | 6 s |
| `Regroup` | On se regroupe | Regroup | vert | `o` | 6 s |
| `Thanks` | Merci ! | Thanks! | rose | `<3` | 3 s (au-dessus du joueur) |

### 7.1 Déclenchement

| Appareil | Ping rapide (contextuel) | Roue des 6 |
| --- | --- | --- |
| PC | clic molette ou G (action `Ping`) au point visé par la souris | maintenir l'action `Ping` 0,3 s, puis cliquer une option |
| Téléphone / tablette | bouton Ping (48 px) : point au centre de l'écran | appui long sur la mini-carte (point touché) ou appui long sur le bouton Ping |
| Manette | croix haut (action `Ping`) au centre de l'écran | maintenir 0,3 s ; sélection manette sur la roue (`SelectedObject`), B ferme |

Ping contextuel : près de la position du boss (< 40 studs) → `Boss` ; autel < 15 → `Shrine` ; coffre < 10 → `Chest` ; sinon `Regroup`.

### 7.2 Affichage

Marqueur monde (`BillboardGui` toujours devant, 8 en pool) : glyphe dans un rond coloré + texte + nom du joueur ; flèche de bord d'écran quand hors champ ; point sur la mini-carte ; ligne dans le fil (« Alex : Autel »). Aucun son (pas d'id d'asset) — TODO quand les sons existent.

### 7.3 Serveur (PingService)

- `Net.onServerEvent("Ping", 3, …)` (seau de 3 par seconde) + plafond 6 pings / 10 s par joueur.
- Vérifie : `kind` est une chaîne parmi les 6 ; `position` est un `Vector3` fini (pas NaN / inf, |x|,|y|,|z| < 100 000) et à ≤ 300 studs de la racine du personnage de l'émetteur (les fantômes peuvent pinger s'ils ont un personnage).
- Diffuse `PingBroadcast { userId, kind, position }` aux joueurs de la run (`RunManager.getRunPlayers()` si l'émetteur en fait partie, sinon tous les joueurs du serveur — mode test).

---

## 8. Boutons tactiles (bas droite)

| Bouton | Taille | Position (depuis le coin bas droit, échelle 1) | Action |
| --- | --- | --- | --- |
| Saut | 84 | (−20, −24) | `Jump` (maintenu = plané) |
| Glisser | 64 | à gauche du Saut, écart 12 | `Slide` |
| Ultime | 64 | au-dessus du Saut, écart 12 | `Ultimate` ; jauge circulaire (`ultimateCharge` 0..1), brille quand pleine (statique si flashs réduits) |
| Ping | 48 | au-dessus du Glisser | `Ping` (tap = rapide, appui long = roue) |

Passe finale : on lit les rectangles réels et on écarte les boutons qui se chevauchent (Responsive UI §6). Masqués hors tactile, sauf la jauge d'Ultime qui reste en affichage (non cliquable) avec l'indication de touche.

---

## 9. Écran de sélection (LoadoutUI)

Visible en phase `Loadout` (et au premier lancement avant le premier `RunState`).

- **Gauche (40 %)** : aperçu du personnage du joueur dans un `ViewportFrame` qui tourne lentement sur un socle (arrêté si mouvement réduit). Le trait de classe est ajouté par le domaine avatar (pas de faux trait ici).
- **Droite** : onglets **Classe** / **Compagnon**.
  - Grille de 10 classes (cartes 120×80 ; 2 colonnes téléphone, 3 tablette, 5 PC) : nom, arme de départ, maîtrise « M 4 » si connue. Verrouillée : cadenas dessiné + grisé + **indice de déblocage** (« Quête : encaisser 50 000 dégâts », texte de la quête si Config.Quests le fournit, sinon l'id de la quête).
  - Grille de 6 compagnons : nom du stade 1, affinité, Lien « L 3 ». Même règle de verrou.
- **Bas** : bouton **JOUER / PLAY** 220×56 → `SelectLoadout(classId, companionId)`. Après l'envoi : « En attente des autres joueurs… ».
- Données : `Profile` (unlocks, mastery, bond, loadout). Avant le profil : classes gratuites Cornu, Plumeline, Mecano ; compagnons marqués `free` dans Config.Companions, sinon Braise, Ronce, Maree.
- Les cosmétiques ne sont que du style (11.3) : aucune stat affichée sur un cosmétique.

---

## 10. Écran de fin (EndScreen)

`RunSummary` → panneau centré (90 % largeur, ≤ 720) défilant :

1. Titre « VICTOIRE ! » / « VICTORY! » ou « FIN DE LA RUN » / « RUN OVER », monde · tier · stage atteint.
2. Ligne de chiffres : ennemis vaincus, niveau, pièces, autels, coffres, relèves, Vague Finale (s).
3. **Dégâts par arme** : barres horizontales triées, nom de l'arme + valeur abrégée (12,4 k), barre = part du maximum.
4. **Quêtes avancées** : barre de progression par quête (`progress / goal`), « TERMINÉE » + coche dessinée si `completed`.
5. Étoiles d'argent gagnées (`silverEarned`).
6. Bouton **REJOUER / PLAY AGAIN** 240×64 mis en avant (couleur primaire) → `Replay()`. Désactivé 1 s après envoi.

Masqué quand la phase repasse à `Loadout` ou `Running`.

---

## 11. Réglages (SettingsUI)

Bouton engrenage 44 px (sous la mini-carte en run, en haut à droite sur l'écran de sélection). Panneau 340 px :

| Réglage | FR / EN | Effet | Envoi |
| --- | --- | --- | --- |
| Mode daltonien | Mode daltonien / Colorblind mode | palette alternative (raretés, mini-carte, pings) | `UpdateSettings{colorblind}` |
| Réduire les flashs | Réduire les flashs / Reduce flashes | pas de clignotements, pas de pulsations, fondus seulement ; activé par défaut si `GuiService.ReducedMotionEnabled` | `{reduceFlashes}` |
| Taille du texte | Taille du texte / Text size : 100 % · 115 % · 130 % | multiplie nos `TextSize` (en plus de `PreferredTextSize` du moteur) | `{textScale}` |
| Garder mon chapeau | Garder mon chapeau / Keep my hat | lu par le domaine avatar | `{keepHat}` |
| Langue | Auto · Français · English | local seulement (pas de champ dans le contrat) | — |
| Légende de la mini-carte | — | affiche le tableau §6 | — |

Les réglages arrivent de `Profile.settings` ; envoi limité à 1 par 0,5 s (regroupé).

---

## 12. Accessibilité

- Les trois préférences `GuiService` respectées et écoutées : `PreferredTextSize` (texte fixe, jamais `TextScaled`), `PreferredTransparency` (transparence des fonds × valeur), `ReducedMotionEnabled` (fondus au lieu de pops, rien qui tourne).
- Daltonisme : palettes par jetons sémantiques + 2e canal partout (losanges, formes, texte).
- Contraste ≥ 4,5:1 pour le texte (texte blanc sur fonds `#1C2230`, contour noir 1 px sur les nombres au-dessus du jeu).
- Aucun clignotement > 3 Hz, aucun flash plein écran, même hors mode réduit.
- Sous-titres : toutes les annonces sont du texte.
- Gros boutons (≥ 44 px), pas d'action critique en appui long seulement (la roue a toujours un équivalent).

## 13. Localisation

- Tout texte visible est `{ fr, en }` (Config.UI.Strings, ou `LocalizedText` reçu du serveur). Anglais par défaut.
- Langue : réglage local, sinon `Translator.LocaleId` du joueur (`GetTranslatorForPlayerAsync` dans un `pcall`, écoute de `LocaleId`), sinon `LocalizationService.RobloxLocaleId`. « fr » si l'id commence par `fr`.
- **`AutoLocalize = false` sur toutes nos guis** : le texte est déjà traduit par nos soins, et les noms inventés (classes, compagnons, armes, boss) ne doivent pas être capturés par la traduction automatique ; les nombres et noms de joueurs non plus (Localization §2).
- Phrases complètes avec paramètres nommés (`"{name} est à terre !"`), jamais de concaténation de fragments ; pas de logique de pluriel anglaise.
- Changement de langue en jeu : tous les textes enregistrés auprès du thème sont réécrits.

## 14. Performance

- Zéro code par image au repos. Boucles par image uniquement pendant : anneau de 8 s, flèche du boss visible, flèches de bord des pings, aperçu tournant de l'écran de sélection. Chaque boucle est connectée/déconnectée.
- Chrono 4 Hz, mini-carte 10 Hz, textes réécrits seulement si la valeur change.
- Pools : marques de mini-carte, marqueurs de pings, lignes du fil, barres de l'écran de fin.
- Aucune création d'instance dans les mises à jour fréquentes ; pas de table allouée par image.
- La partie animée (mini-carte, flèches) est dans ses propres petites guis.

## 15. Câblage des entrées

`InputController` (domaine avatar) possède le système d'actions. Côté UI (module d'aide `UIInput`) :

- écoute : `InputController.onAction(name, fn(pressed))` pour `Card1`–`Card3` (CardUI) et `Ping` (PingUI) ;
- boutons tactiles : `InputController.bindButton(name, button)` s'il existe (liaison `UIButton` du moteur), sinon `InputController.trigger(name, pressed)` sur appui/relâche, sinon repli direct : `Ultimate` → remote `CompanionUltimate`, `Jump` → `Humanoid.Jump`, `Ping` → ping rapide ;
- sans InputController : touches 1/2/3 et clic molette lus par `UserInputService` (en vérifiant `gameProcessedEvent`).

---

## Sources vault

- 05 UI and UX / **Responsive UI for Phone Tablet Console and PC** — profil d'appareil (petit côté < 520), 12 px / 44 px / 8 px, plancher d'échelle, règles du HUD téléphone, passe anti-chevauchement.
- **Safe Areas and Insets** — `ScreenInsets` explicite, `SafeAreaCompatibility = None`, `TopbarInset` jamais en dur (Roblox docs).
- **Mobile Button Layout Editor** — boutons dans le conteneur sûr, positions en échelle, liaison `UIButton`.
- **UI Design Systems** §3–4 — module de thème vs `StyleSheet` (style moteur, éditeur bêta oct. 2026).
- **AI Pitfalls - UI and Input** — `UIScale` jamais imbriqué, vues de test.
- **HUD Design** — zones, file d'annonces, budgets de mouvement et de performance (« write only on change »).
- **Accessibility** — `PreferredTextSize`, `PreferredTransparency`, `ReducedMotionEnabled` (Roblox docs).
- **Colour-Blind Safe Design** — jetons sémantiques, palettes par mode, 2e canal, pas de filtre `ColorCorrectionEffect`.
- **Motion Sensitivity and Camera Comfort** — mouvement réduit = fondu.
- **Text Fonts and Rich Text** — `FontFace`, piège Gotham, échelle typographique.
- **Localization** — `AutoLocalize = false` pour noms inventés, nombres et textes de script ; `GetTranslatorForPlayerAsync` en `pcall` et écoute de `LocaleId` (Roblox docs).
- **Input - UserInputService and ContextActionService** §5 — Input Action System (`InputContext`, `InputAction`, `InputBinding.UIButton`, `Fire()`), `Activated`, `gameProcessedEvent`.
- **Minimap and World Map UI** — nord = monde −Z, projection unique, pas de rotation sans `CanvasGroup`.
- **Race HUD** — chrono calculé localement, pas de texte envoyé par image.
- **Notification and Toast Systems** — le serveur envoie un type + paramètres, le client formate.
- **SYMPTOMS.md** — `DisplayOrder` explicite, `ResetOnSpawn = false`, contour ≤ 7 %, pop via `UIScale`, plancher d'échelle.
