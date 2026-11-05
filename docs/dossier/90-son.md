# 90 — Son (A10, partie code)

Décisions : `01-decisions-v2.md` §8 (bibliothèque sous licence du Creator Store) et §12 (rien n'est construit par script).
Code : `client/Controllers/SoundController.luau`. Réglages et correspondances : `shared/Config/Sounds.luau`.

## 1. Principe

Clément pose chaque son comme un objet `Sound` dans `ReplicatedStorage.Assets.Sounds` (sous-dossiers libres, par exemple `Music`, `Weapons`, `UI`) ou dans `SoundService`. Le **nom** de l'objet est la clé : le code le trouve par son nom, le clone dans `SoundService.COHUE_SoundPool` et le joue. Le SoundId, le volume de base, la hauteur (`PlaybackSpeed`) et les effets (égaliseur, réverb…) se règlent **sur l'objet** dans Studio ; le code ne fait que multiplier.

Un son absent ne casse rien : il est signalé une fois dans la sortie (`[SoundController] Sound "X" introuvable`) puis ignoré.

## 2. Mixage (A10-03, A10-05)

Volume joué = volume de l'objet × volume de l'événement × volume de la catégorie × réglage joueur × master.

| Catégorie | Réglage joueur | Volume | Sons simultanés max | Plein |
| --- | --- | --- | --- | --- |
| Music | music | 0,5 | 6 | ignore le nouveau |
| Ambience | music | 0,35 | 2 | ignore |
| Weapons | sfx | 0,45 | 8 | coupe le plus ancien |
| KO | sfx | 0,5 | 6 | coupe le plus ancien |
| Creatures | sfx | 0,55 | 4 | coupe le plus ancien |
| UI | sfx | 0,7 | 4 | coupe le plus ancien |

Limite globale : 24 sons courts en même temps. Chaque événement a un délai minimal entre deux lectures (cooldown) et une variation de hauteur aléatoire contre la répétition (tirs, KO, ramassage).

Sons « positionnés » (KO, impacts, télégraphes de boss, pings) : vue de dessus, donc pas de stéréo ; volume plein à moins de 25 studs du personnage, 20 % à 90 studs, rien au-delà.

Réglages joueur : `master`, `music`, `sfx` (0..1, défaut 1 / 0,7 / 1). API : `SoundController.getVolume(group)`, `setVolume(group, value)`, signal `volumeChanged`. Lus dans `Profile.settings` (`masterVolume`, `musicVolume`, `sfxVolume`) dès que le serveur les garde ; en attendant (`Config.Sounds.Volumes.Persist = false`) le réglage vaut pour la session.

## 3. Musique (A10-04)

Une piste à la fois, fondu enchaîné de 1,5 s. Choix :

1. lobby / choix du personnage (`phase = Loadout`) : `Music_Lobby` ;
2. combat de boss (`phase = Boss`) : `Music_Boss_<bossId>` s'il existe, sinon `Music_Boss` ;
3. Overtime (`RunState.overtime`) : `Music_Overtime`, dynamique (ci-dessous) ;
4. sinon : la musique du monde (`Music_<worldId>`), plus l'ambiance du monde en boucle (`Amb_<worldId>`) pendant toute la run ;
5. fin de run : silence, jingle de victoire ou de défaite.

**Overtime dynamique** : intensité = secondes d'Overtime / 240 (plafonnée à 1). La piste principale accélère de ×1,0 à ×1,1 et monte de 0,85 à 1,1 en volume. Deux couches entrent en fondu de 2 s : `Music_Overtime_Layer2` à 25 % d'intensité (1 min), `Music_Overtime_Layer3` à 60 % (2 min 24). Les couches sont recalées sur la piste principale : **elles doivent avoir le même tempo et la même longueur** que `Music_Overtime` (stems d'un même morceau). Sans couches, seule l'accélération joue.

## 4. Sons à fournir par Clément

Tous des objets `Sound` nommés exactement ainsi. Les musiques et ambiances en `Looped` n'importe (le code force la boucle) ; les autres sont des sons courts.

### Musiques et ambiances

| Nom | Catégorie | Usage |
| --- | --- | --- |
| `Music_Lobby` | Music | Lobby et choix du personnage, joyeuse, en boucle |
| `Music_BoisGrognon` | Music | Monde 1 |
| `Music_DunesCroustillantes` | Music | Monde 2 |
| `Music_RecreFantome` | Music | Monde 3 |
| `Music_Boss` | Music | Combat de boss (commune) |
| `Music_Boss_GrandCheneRonchon`, `Music_Boss_PharaonGrillePain`, `Music_Boss_DirectriceEternelle`, `Music_Boss_GrandBrouhaha` | Music | Facultatif : musique propre à un boss |
| `Music_Overtime` | Music | Overtime, piste principale |
| `Music_Overtime_Layer2`, `Music_Overtime_Layer3` | Music | Facultatif : couches d'intensité (stems du même morceau) |
| `Stinger_BossDefeated` | Music | Jingle, boss vaincu |
| `Stinger_Victory` | Music | Jingle, victoire / Cash out |
| `Stinger_Defeat` | Music | Jingle, défaite |
| `Amb_BoisGrognon`, `Amb_DunesCroustillantes`, `Amb_RecreFantome` | Ambience | Ambiance de fond par monde, en boucle |

### Armes (catégorie Weapons)

`Weapon_<id>_Fire` (tir) et `Weapon_<id>_Hit` (impact) pour les 16 armes : `HacheBoomerang`, `PlumesDards`, `CleTourelle`, `GriffesEclair`, `PoingSeisme`, `NuageSpores`, `SouffleBraise`, `Meteorite`, `EclatsPrisme`, `FouetTentacule`, `ToupieScie`, `BouleBowling`, `CerfVolantLaser`, `ParapluieBouclier`, `BombePaillettes`, `PistoletBulles`.
Minimum pour commencer : `Weapon_Default_Fire` et `Weapon_Default_Hit`, joués pour toute arme sans son propre.

### KO (catégorie KO)

| Nom | Usage |
| --- | --- |
| `KO_Default` | KO d'ennemi, par défaut (minimum) |
| `KO_Swarm`, `KO_Jumper`, `KO_Shooter`, `KO_Armored`, `KO_MiniBoss`, `KO_Boss` | Facultatif : KO par famille |
| `KO_<nom>` (ex. `KO_GlandGrincheux`) | Facultatif : KO propre à un ennemi (`name` de Config.Enemies) |
| `SFX_XpPickup` | Ramassage d'XP (très court, joué souvent) |
| `SFX_CoinPickup` | Ramassage de pièces |
| `SFX_PlayerHurt` | Le joueur prend un coup |

### Créatures (catégorie Creatures)

| Nom | Usage |
| --- | --- |
| `Creature_<famille>_Attack` | Attaque (bond, tir) par famille : Swarm, Jumper, Shooter, Armored, MiniBoss |
| `Creature_<famille>_Spawn` | Facultatif : apparition (surtout MiniBoss) |
| `Creature_Boss_Roar` | Le boss apparaît |
| `Creature_Boss_Telegraph` | Le boss prépare une attaque (zone au sol) |

Comme pour les KO, `Creature_<nom>_Attack` remplace la famille pour un ennemi précis.

### Interface et annonces (catégorie UI)

| Nom | Usage |
| --- | --- |
| `UI_Click` | Tout bouton (automatique) |
| `UI_CardOffer` / `UI_CardPick` | Cartes de niveau : apparition / choix |
| `UI_Purchase` | Achat (boutique) |
| `UI_Notify` | Notification |
| `UI_QuestComplete` | Quête terminée |
| `UI_EggHatch` | Œuf éclos |
| `UI_Ping` | Ping d'un coéquipier |
| `SFX_LevelUp` | Niveau gagné |
| `SFX_ChestOpen` | Coffre ou récompense de marchand |
| `SFX_ShrineReward` | Autel chargé, choix de récompense |
| `SFX_CompanionEvolve` | Le compagnon évolue |
| `SFX_UltimateReady` | Ultime du compagnon prêt |
| `SFX_CaptureCharge` / `SFX_CaptureSuccess` | Capture : chargement / réussite |
| `SFX_PlayerDowned` | Le joueur est à terre |
| `Announce_StageStart` | Début de monde |
| `Announce_Wave` | Vague |
| `Announce_MiniBoss` | Mini-boss |
| `Announce_ArcheRevealed` | Arche du boss trouvée |
| `Announce_Countdown` | Décompte d'arène (tic) |
| `Announce_Overtime` | Début de l'Overtime |
| `Announce_OvertimeStep` | Palier d'Overtime (toutes les 30 s) |
| `Announce_Hazard` | Danger du monde |
| `Announce_Portal` | Portail ouvert |
| `Announce_TeammateDowned` | Un coéquipier à terre ou mort |
| `Announce_Revived` | Relevé |

Minimum jouable : `Music_Lobby`, une `Music_<monde>`, `Music_Boss`, `Music_Overtime`, `Weapon_Default_Fire`, `Weapon_Default_Hit`, `KO_Default`, `SFX_XpPickup`, `SFX_CoinPickup`, `SFX_LevelUp`, `UI_Click`, `UI_CardOffer`, `UI_CardPick`, `Stinger_Victory`, `Stinger_Defeat`.

## 5. Branchements

Écouté directement (remotes du contrat) : RunState (musique, Overtime, boss vaincu), Announce, PlayerProgress (XP, niveau), Coins, CardOffer, PlayerVitals (coup, à terre), BossState (cri, télégraphes, musique du boss), CompanionState (évolution, ultime), ShrineOffer, LootReward, EggHatched, DataNotice, PingBroadcast, Profile (réglages), CaptureState s'il existe. Clic : tout `GuiButton` du PlayerGui (attribut `NoClickSound = true` pour le couper, `ClickSound = "<clé>"` pour le changer).

Par API (à appeler par les modules qui décodent déjà les snapshots, voir contract requests) :
- `SoundController.weapon(weaponId, "Fire" | "Hit", position?)` — WeaponFX ;
- `SoundController.enemy(kind, "KO" | "Attack" | "Spawn", position?)` — EnemyRenderer, EnemyAttackFX ;
- `SoundController.play(key, position?)` — tout événement de `Config.Sounds.Events` (ex. `Purchase` depuis la boutique).

Récupération côté appelant, sans dépendance dure : `local sound = Registry.find("SoundController"); if sound then sound.weapon(id, "Fire", pos) end`.
