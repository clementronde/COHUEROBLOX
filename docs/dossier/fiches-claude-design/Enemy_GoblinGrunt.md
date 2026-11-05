# Fiche Claude Design : Goblin Grunt (`Enemy_GoblinGrunt`)

## En bref, pour Clément

L'ennemi le plus courant du monde 1 (Bois Grognon) : un petit gobelin vert de mêlée qui fonce sur le joueur, une cocotte rouge sur la tête et une louche brandie. Il est lu en un coup d'œil dans une horde de 70 grâce à sa cocotte rouge, vue d'en haut.

- **Taille** : 4,5 studs, de la semelle au bouton de la cocotte.
- **Face** : vers −Z, comme ton fantôme.
- **Pièces** : 6 au plus.
  - Le corps, d'un bloc.
  - Les deux jambes.
  - Le bras droit avec la louche.
  - Le bras gauche.
  - La cocotte, qui s'envole à la mort.
- **Animations** : marche en canard, coup de louche, recul quand il est touché, mort qui fait sauter la cocotte.
- **Budget** : 800 triangles au plus, car il y en aura des centaines à l'écran.
- **Style** : celui de ton fantôme, choisi le 5 nov. : voxels lisses, deux tons par couleur, yeux noirs avec un reflet blanc.
- **Image de référence** : [ref/Enemy_GoblinGrunt.png](ref/Enemy_GoblinGrunt.png), tirée de la planche concept d'A03. Elle sert pour la forme et les gags ; les tenons ne sont pas à reprendre.

Colle dans Claude Design tout le bloc « Prompt » ci-dessous, avec l'image de référence et une capture de ton fantôme.

---

## Prompt (à coller dans Claude Design)

```text
Create a 3D voxel enemy for a Roblox survivors-like game (huge hordes, played mostly on phones, players aged 9–15).
Export a GLB for Roblox Import 3D, plus a Roblox controller script, exactly like the "Voxel Ghost for Roblox"
handoff: one MeshPart per colour, hex code at the end of each mesh name, moving parts separated, a README.

STYLE: exactly the same style as the "Voxel Ghost" (attach its picture): chunky voxels, SmoothPlastic, flat colours
with two tones per material (a base colour and a slightly darker shade), black eyes with a small white Neon glint,
small pastel cheeks allowed. No studs, no textures. The attached goblin picture is for shape and gags only.

CHARACTER — "Goblin Grunt", the most common enemy of the forest world. A small, angry, slightly ridiculous goblin
that charges the player and bonks them with a kitchen ladle. Tone: absurd humour, cute-grumpy, never scary.

SILHOUETTE (must read as a black shape at 64 px):
- A "T" shape: a big square head with two long horizontal pointy ears sticking out sideways (each ear about as
  long as half the head width, tips slightly raised).
- Big head (about 45 % of the height), short stubby legs, small round belly.
- On the head, worn as a helmet: an upside-down red cast-iron cooking pot (a Dutch oven) with a small black knob on
  top and two small black handles on its sides at mid-height. The pot is straight-walled, as wide as the head plus
  one voxel, with a darker red rim where it sits on the head. Seen from above, the red pot with its black knob is
  what identifies this enemy in a crowd.
- Right hand (the character's right, on the −X side): raises a long kitchen ladle straight up next to the head.
  Steel handle, round hollow bowl at the top (the bowl is clearly a scoop, seen from the front and from above).
- Left arm: bare, hanging, slightly out from the body.

FACE (front = −Z):
- Two big black eyes, like the Voxel Ghost's, each with a small white Neon glint, looking slightly inward (a little
  cross-eyed). They must stay readable from far away.
- Thick angry eyebrows (darker green), inner ends lower.
- A big green nose between the eyes.
- An OPEN mouth below the nose: dark purple inside, two crooked cream teeth at the top, a small dark-red tongue.
  Never a black horizontal bar under the nose (it reads as a moustache).

CLOTHES: a red tunic (same red as the pot), a brown leather belt with a small gold buckle, brown shoes.

PALETTE (use only these colours; put the hex at the end of each mesh name):
- skin            8FD13F   (lime green)
- skin_shadow     6C923E   (ear insides, legs, brows, hands)
- tunic_red       E63946   (tunic and pot)
- red_dark        A42F43   (pot rim and lid)
- knob_ink        1C1726   (pot knob, pot handles)
- eye_black       120C1F   (eyes, like the ghost)
- eye_glint       FFFFFF   (Neon, tiny)
- teeth_cream     FFE8B8
- mouth_dark      37274D
- leather_brown   6E4227   (belt, shoes)
- buckle_gold     FFC21A   (tiny, under 5 % of the model)
- steel           8EA6C2   (ladle handle)
- steel_light     B6C1CA   (ladle bowl)
- steel_dark      525372   (inside of the ladle bowl)

SIZE AND ORIENTATION:
- Final height 4.5 studs from sole to pot knob (about 18 voxels of 0.25 stud). If you export at another scale,
  say the scale in the README; we rescale on import.
- Face towards −Z (Roblox LookVector), like the Voxel Ghost. Feet on Y = 0, centred on X = 0 and Z = 0.

PARTS TO SEPARATE (moving parts), with these exact names + _<material>_<HEX> suffixes:
- body_*      : head, torso, belly, face, ears (everything that does not move on its own)
- leg_L, leg_R : each leg with its shoe (pivot at the hip)
- arm_R        : right arm + the ladle (pivot at the shoulder)
- arm_L        : left arm (pivot at the shoulder)
- hat_*        : the pot, knob and handles (it pops off on death)
Name examples: body_skin_8FD13F, body_tunic_red_E63946, hat_pot_red_E63946, arm_R_steel_8EA6C2.

BUDGET (this enemy appears by the hundreds on a phone):
- 800 triangles maximum for the whole model, all parts included. Merge voxels into large flat faces (greedy
  meshing), no hidden inner faces.
- At most 8 meshes in total: merge tiny details into the nearest colour mesh rather than adding a mesh.
- No textures, no transparency, no glow (no Neon) on the body.

ANIMATIONS (in the controller script, on anchored parts, like the ghost's GhostController):
- Walk (loop, about 2 strides per second): angry waddle. Legs swing ±25° around the hips, body bobs up 0.15 stud
  twice per stride and rolls ±6°, ears flop slightly, the ladle arm sways.
- Attack (0.7 s): wind-up 0.25 s (ladle raised behind the head, body leans back), smash 0.1 s (ladle comes down in
  front, body leans forward, a small dust puff on the ground in front), recover 0.35 s.
- Hit (0.15 s): flinch backwards, the pot wobbles.
- Death (0.5 s): the pot pops up spinning, the body squashes flat and vanishes in a small puff of cream smoke.
- Attributes on the Model, like the ghost: Walking (bool), AutoAttack (bool), AttackEvery (number, 1.5 s),
  Attack (set to os.clock() to trigger), Dead (set to true to play the death).

EFFECTS (keep them small and matte — light is reserved for the player's weapons):
- Smash: a soft dust ring on the ground in front (cream/light brown smoke, no glow), a few small debris bits.
- Death: a small cream smoke puff.

DO NOT:
- No Christmas elf look: no white fur band on the hat.
- No Mario look: no red cap + big nose + black moustache. The mouth is open with teeth.
- No Clash of Clans goblin look: no loot sack, no gold everywhere.
- Never use cyan / light blue (reserved for XP pick-ups) or pink (reserved for the capture effect).
- No Neon or glow on the goblin itself except the eye glints; gold only as the tiny buckle.
- No text, no logos, no signs.
```

---

## Notes pour l'emballage dans COHUE (A03, à ton signal)

- **Nom** : `Enemy_GoblinGrunt`.
- **Dossier** : `ReplicatedStorage.Assets.Creatures`.
- **Pivot** : les pieds au sol ; la face vers −Z.
- **Attributs** : `Height` 4,5 · `Radius` 1,3 · `Float` 0 · `Family` Goblin · `Role` Melee.
- Les gobelins v1 d'A01 vont dans `ServerStorage.A03_Backup` (dossier 13 §9).

---
