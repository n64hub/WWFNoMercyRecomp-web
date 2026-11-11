// Where WWF No Mercy is, for the plans: which code overlay the game has at 0x80106760, by its third word (a jal into
// its own code): the menus' (ROM 0x0AE390) or the 3D engine's (ROM 0x081210), which the intro and a match run.
window.overlay = () => ({ 0x0c0422c4: 'menus', 0x0c041a01: 'engine' })[n64r(0x80106768)] ?? 'other';
true;
