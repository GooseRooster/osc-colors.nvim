---@alias osc-colors.HexColor string

---Probed terminal color capability (see `osc-colors.capability`).
---@class osc-colors.Capability
---@field tier "truecolor"|"256"|"unknown"
---@field evidence? { reason?: string, signals?: table }

---@class osc-colors.ColorTransform
---@field darken? string
---@field lighten? string
---@field amount number

---@alias osc-colors.ColorValue
---| osc-colors.HexColor
---| osc-colors.ColorTransform

---@class osc-colors.PaletteColor
---@field normal? osc-colors.HexColor
---@field bright? osc-colors.HexColor
---@field dim? osc-colors.HexColor

---@class osc-colors.PaletteNamed
---@field black osc-colors.PaletteColor
---@field gray osc-colors.PaletteColor
---@field white osc-colors.PaletteColor
---@field red osc-colors.PaletteColor
---@field orange osc-colors.PaletteColor
---@field yellow osc-colors.PaletteColor
---@field green osc-colors.PaletteColor
---@field cyan osc-colors.PaletteColor
---@field blue osc-colors.PaletteColor
---@field magenta osc-colors.PaletteColor
---@field brown osc-colors.PaletteColor

---@class osc-colors.UiGlobal
---@field background { normal: osc-colors.HexColor }
---@field foreground { normal: osc-colors.HexColor }

---@class osc-colors.UiCursor
---@field background { normal: osc-colors.HexColor }
---@field foreground { normal: osc-colors.HexColor }

---@class osc-colors.UiChrome
---@field background { normal: osc-colors.HexColor, dark: osc-colors.HexColor }
---@field foreground { normal: osc-colors.HexColor, dark: osc-colors.HexColor }

---@class osc-colors.UiHighlight
---@field line { background: osc-colors.HexColor }
---@field text { background: osc-colors.HexColor }
---@field search { background: osc-colors.HexColor, foreground: osc-colors.HexColor }

---@class osc-colors.UiStatus
---@field error osc-colors.HexColor
---@field warning osc-colors.HexColor
---@field info osc-colors.HexColor
---@field success osc-colors.HexColor

---@class osc-colors.Ui
---@field global osc-colors.UiGlobal
---@field cursor osc-colors.UiCursor
---@field gutter { foreground: osc-colors.HexColor }
---@field border { normal: osc-colors.HexColor }
---@field chrome osc-colors.UiChrome
---@field selection { background: osc-colors.HexColor }
---@field highlight osc-colors.UiHighlight
---@field status osc-colors.UiStatus

---@class osc-colors.SyntaxString
---@field default osc-colors.HexColor
---@field regexp osc-colors.HexColor
---@field other osc-colors.HexColor

---@class osc-colors.SyntaxConstantNumeric
---@field default osc-colors.HexColor
---@field float osc-colors.HexColor

---@class osc-colors.SyntaxConstantCharacter
---@field default osc-colors.HexColor
---@field escape osc-colors.HexColor

---@class osc-colors.SyntaxConstant
---@field default osc-colors.HexColor
---@field character osc-colors.SyntaxConstantCharacter
---@field language osc-colors.HexColor
---@field builtin osc-colors.HexColor
---@field numeric osc-colors.SyntaxConstantNumeric

---@class osc-colors.SyntaxEntityNameFunction
---@field default osc-colors.HexColor
---@field constructor osc-colors.HexColor

---@class osc-colors.SyntaxEntityName
---@field class osc-colors.HexColor
---@field type osc-colors.HexColor
---@field ["function"] osc-colors.SyntaxEntityNameFunction
---@field label osc-colors.HexColor
---@field namespace osc-colors.HexColor
---@field tag osc-colors.HexColor

---@class osc-colors.SyntaxEntity
---@field name osc-colors.SyntaxEntityName
---@field other { ["attribute-name"]: osc-colors.HexColor }

---@class osc-colors.SyntaxKeywordControl
---@field default osc-colors.HexColor
---@field import osc-colors.HexColor
---@field flow osc-colors.HexColor

---@class osc-colors.SyntaxKeyword
---@field default osc-colors.HexColor
---@field control osc-colors.SyntaxKeywordControl
---@field operator osc-colors.HexColor
---@field declaration osc-colors.HexColor

---@class osc-colors.SyntaxVariable
---@field default osc-colors.HexColor
---@field parameter osc-colors.HexColor
---@field builtin osc-colors.HexColor
---@field other { property: osc-colors.HexColor }

---@class osc-colors.SyntaxMarkup
---@field default osc-colors.HexColor
---@field heading osc-colors.HexColor
---@field raw osc-colors.HexColor
---@field link osc-colors.HexColor
---@field list osc-colors.HexColor
---@field inserted osc-colors.HexColor
---@field deleted osc-colors.HexColor

---@class osc-colors.Syntax
---@field comment osc-colors.HexColor
---@field string osc-colors.SyntaxString
---@field constant osc-colors.SyntaxConstant
---@field entity osc-colors.SyntaxEntity
---@field keyword osc-colors.SyntaxKeyword
---@field storage { type: osc-colors.HexColor, modifier: osc-colors.HexColor }
---@field variable osc-colors.SyntaxVariable
---@field punctuation { separator: osc-colors.HexColor, section: osc-colors.HexColor }
---@field markup osc-colors.SyntaxMarkup
---@field meta { preprocessor: osc-colors.HexColor }

---Semantic role colors -- the single source of truth for diagnostics,
---errors, and diffs. In base16 mode these mirror the static slot
---assignments; in soul mode they're regenerated from role math with
---conventional hue-sector anchoring (see `osc-colors.roles`).
---@class osc-colors.Semantics
---@field error osc-colors.HexColor
---@field warning osc-colors.HexColor
---@field info osc-colors.HexColor
---@field hint osc-colors.HexColor
---@field success osc-colors.HexColor
---@field deprecated osc-colors.HexColor
---@field diff { add: osc-colors.HexColor, delete: osc-colors.HexColor, change: osc-colors.HexColor }

---Result of roles.generate: resolved role colors and styles, the extracted
---soul, the group -> family assignment, and the cube-snapper (nil outside
---the 256 tier).
---@class osc-colors.RoleGeneration
---@field roles table<string, string> role name -> hex
---@field styles table<string, table> role name -> text attributes (italic/bold)
---@field soul osc-colors.Soul
---@field assignment table<string, string> role group -> family name
---@field snap? fun(hex: string): string

---One of the scheme's own colors, scored by how much the designer
---invested in it (see `osc-colors.soul`).
---@class osc-colors.SoulFamily
---@field name string e.g. "red", or "bright_red" when the bright has its own hue
---@field aliases string[] names folded into this family (near-identical colors)
---@field hex osc-colors.HexColor
---@field L number
---@field C number
---@field H number
---@field shade? { hex: osc-colors.HexColor, L: number, C: number, H: number } bright variant of the same hue
---@field rel number chroma relative to the sRGB gamut at this L/H (0-1)
---@field vivid number rel normalized to the scheme's most vivid family
---@field cohesion number closeness to the scheme's other vivid colors
---@field shift number how far the hue sits from the stock ANSI position (0-1)
---@field salience number blended score; higher = more characteristic
---@field canon number
---@field order integer

---@class osc-colors.Soul
---@field variant "dark"|"light"
---@field bg? osc-colors.HexColor
---@field fg? osc-colors.HexColor
---@field bg_L number
---@field fg_L number
---@field anchors table[] the queried ANSI 1-6 colors (gray ones included)
---@field families osc-colors.SoulFamily[] in ANSI order
---@field ranked osc-colors.SoulFamily[] by salience, descending
---@field dominant? osc-colors.SoulFamily
---@field dominant_hue number
---@field chroma_median number
---@field chroma_max number
---@field achromatic boolean no family survived the gray threshold

---@class osc-colors.Palette
---@field variant "dark"|"light"
---@field palette osc-colors.PaletteNamed
---@field ui osc-colors.Ui
---@field syntax osc-colors.Syntax
---@field semantics osc-colors.Semantics
---@field capability? osc-colors.Capability
-- The terminal's *actual* 256-color cube (OSC 4 slots 16-255), keyed on the
-- cterm slot index. Present only when a cube round ran and the terminal
-- answered; consumers must handle its absence.
---@field cube? table<integer, osc-colors.HexColor>
-- The terminal's bright ANSI colors (OSC 4 slots 9-14), keyed by hue name
-- (red, green, yellow, blue, magenta, cyan). Deliberately not stored in the
-- base24 slots, which would change the base16 mapping. May be partial or
-- absent.
---@field brights? table<string, osc-colors.HexColor>
-- Soul-assigned text attributes per role (absent in base16 mode).
---@field role_styles? table<string, table>
-- Internal: set once roles.apply has rewritten the tree; survives
-- colors.normalize so a second soul pass never double-applies.
---@field _soul_applied? boolean
-- Legacy base slot fields (synthesized for backwards compatibility).
---@field base00? osc-colors.HexColor
---@field base01? osc-colors.HexColor
---@field base02? osc-colors.HexColor
---@field base03? osc-colors.HexColor
---@field base04? osc-colors.HexColor
---@field base05? osc-colors.HexColor
---@field base06? osc-colors.HexColor
---@field base07? osc-colors.HexColor
---@field base08? osc-colors.HexColor
---@field base09? osc-colors.HexColor
---@field base0A? osc-colors.HexColor
---@field base0B? osc-colors.HexColor
---@field base0C? osc-colors.HexColor
---@field base0D? osc-colors.HexColor
---@field base0E? osc-colors.HexColor
---@field base0F? osc-colors.HexColor
---@field base10? osc-colors.HexColor
---@field base11? osc-colors.HexColor
---@field base12? osc-colors.HexColor
---@field base13? osc-colors.HexColor
---@field base14? osc-colors.HexColor
---@field base15? osc-colors.HexColor
---@field base16? osc-colors.HexColor
---@field base17? osc-colors.HexColor

---@alias osc-colors.PaletteValue
---| osc-colors.HexColor
---| fun(palette:osc-colors.Palette):osc-colors.HexColor

---@class osc-colors.SchemeSpec
---@field variant? "dark"|"light"
---@field base00? osc-colors.PaletteValue
---@field base01? osc-colors.PaletteValue
---@field base02? osc-colors.PaletteValue
---@field base03? osc-colors.PaletteValue
---@field base04? osc-colors.PaletteValue
---@field base05? osc-colors.PaletteValue
---@field base06? osc-colors.PaletteValue
---@field base07? osc-colors.PaletteValue
---@field base08? osc-colors.PaletteValue
---@field base09? osc-colors.PaletteValue
---@field base0A? osc-colors.PaletteValue
---@field base0B? osc-colors.PaletteValue
---@field base0C? osc-colors.PaletteValue
---@field base0D? osc-colors.PaletteValue
---@field base0E? osc-colors.PaletteValue
---@field base0F? osc-colors.PaletteValue
---@field base10? osc-colors.PaletteValue
---@field base11? osc-colors.PaletteValue
---@field base12? osc-colors.PaletteValue
---@field base13? osc-colors.PaletteValue
---@field base14? osc-colors.PaletteValue
---@field base15? osc-colors.PaletteValue
---@field base16? osc-colors.PaletteValue
---@field base17? osc-colors.PaletteValue

---@class osc-colors.Highlight: vim.api.keyset.highlight
---@field fg? osc-colors.ColorValue
---@field bg? osc-colors.ColorValue
---@field sp? osc-colors.ColorValue

---@alias osc-colors.Highlights table<string, osc-colors.Highlight>
