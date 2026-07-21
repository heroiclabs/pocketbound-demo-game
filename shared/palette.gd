extends Node
class_name Palette

const LIGHTEST: Color = Color8(0x9B, 0xBC, 0x0F) # #9BBC0F
const LIGHT: Color = Color8(0x8B, 0xAC, 0x0F) # #8BAC0F
const DARK: Color = Color8(0x30, 0x62, 0x30) # #306230
const DARKEST: Color = Color8(0x0F, 0x38, 0x0F) # #0F380F

# UI modulate constants
const DIMMED: Color = Color(1, 1, 1, 0.5)       # inactive/disabled element modulate
const INACTIVE: Color = Color(1, 1, 1, 0.55)    # inactive-but-selectable element modulate
const HIGHLIGHT_ROW: Color = Color(1, 1, 0.5)   # player-owned leaderboard row tint
