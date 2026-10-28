extends SceneTree
# Genera el tema visual del juego: res://ui/theme/royal_theme.tres
# Uso (desde la carpeta del proyecto):
#   Godot --headless --path . --script res://tools/build_theme.gd
# Todas las pantallas lo heredan (Project Settings > GUI > Theme > Custom).
# Para retocar colores o tamaños, cambia las constantes de abajo y vuelve a ejecutarlo.

const OUT := "res://ui/theme/royal_theme.tres"

# --- Paleta ---
const INK := Color("15100c")            # fondo más oscuro
const WOOD := Color("2a1d14")           # botones
const WOOD_HI := Color("3b2919")
const WOOD_LO := Color("1a120c")
const PANEL := Color(0.105, 0.075, 0.055, 0.93)
const CARD := Color(0.17, 0.12, 0.085, 0.88)
const BRONZE := Color("7a5c2e")
const BRONZE_DIM := Color("4d3a22")
const GOLD := Color("d4af5a")
const GOLD_LIGHT := Color("f0d48a")
const PARCH := Color("efe3c8")          # texto principal
const PARCH_DIM := Color("b5a386")
const DISABLED_TEXT := Color("7d6f5a")
const CRIMSON := Color("7c231c")
const CRIMSON_HI := Color("a1342a")
const INK_TEXT := Color("2b1d12")       # texto sobre pergamino

const FONT_BODY := "res://fonts/EBGaramond-Variable.ttf"
const FONT_HEAD := "res://fonts/Cinzel-Bold.otf"
const FONT_TITLE := "res://fonts/CinzelDecorative-Bold.otf"

var theme := Theme.new()

func _initialize() -> void:
	var body := _garamond(500)
	var body_bold := _garamond(700)
	var head: Font = load(FONT_HEAD)
	var title: Font = load(FONT_TITLE)

	theme.default_font = body
	theme.default_font_size = 18

	_buttons(head)
	_labels(body, body_bold, head, title)
	_panels()
	_inputs(body)
	_bars_and_sliders(head)
	_tabs_and_popups(body, head)
	_misc(body, body_bold)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(theme, OUT)
	print("Tema guardado en %s (error %d)" % [OUT, err])
	quit()

# --- Ayudas ---

func _garamond(weight: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load(FONT_BODY)
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	return fv

func _box(bg: Color, border: Color = Color.TRANSPARENT, border_w: int = 0, radius: int = 3,
		margin_h: float = 12.0, margin_v: float = 6.0, shadow: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	sb.anti_aliasing = true
	if shadow > 0:
		sb.shadow_size = shadow
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_offset = Vector2(0, 2)
	return sb

func _icon(size: int, draw: Callable) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for x in size:
		for y in size:
			var c: Color = draw.call(Vector2(x + 0.5, y + 0.5), float(size))
			if c.a > 0.0:
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _circle(fill: Color, ring: Color) -> Callable:
	return func(p: Vector2, s: float) -> Color:
		var d := p.distance_to(Vector2(s, s) / 2) / (s / 2)
		if d > 1.0:
			return Color.TRANSPARENT
		var a := clampf((1.0 - d) * s / 2, 0.0, 1.0)
		var c := ring if d > 0.62 else fill
		return Color(c, c.a * a)

func _check_box(checked: bool) -> Callable:
	return func(p: Vector2, s: float) -> Color:
		var m := 2.0
		var inside := p.x > m and p.y > m and p.x < s - m and p.y < s - m
		if not inside:
			return Color.TRANSPARENT
		var border := p.x < m + 2 or p.y < m + 2 or p.x > s - m - 2 or p.y > s - m - 2
		if border:
			return BRONZE if not checked else GOLD
		if checked and p.x > m + 4 and p.y > m + 4 and p.x < s - m - 4 and p.y < s - m - 4:
			return GOLD
		return INK

# --- Secciones ---

func _buttons(head: Font) -> void:
	var normal := _box(WOOD, BRONZE, 2, 3, 16, 8, 3)
	var hover := _box(WOOD_HI, GOLD, 2, 3, 16, 8, 4)
	var pressed := _box(WOOD_LO, GOLD_LIGHT, 2, 3, 16, 9, 1)
	pressed.content_margin_bottom = 7
	var disabled := _box(Color(WOOD, 0.55), BRONZE_DIM, 2, 3, 16, 8)
	var focus := _box(Color.TRANSPARENT, GOLD_LIGHT, 2, 4)
	focus.draw_center = false
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("hover_pressed", type, pressed)
		theme.set_stylebox("disabled", type, disabled)
		theme.set_stylebox("focus", type, focus)
		theme.set_font("font", type, head)
		theme.set_font_size("font_size", type, 15)
		theme.set_color("font_color", type, PARCH)
		theme.set_color("font_hover_color", type, GOLD_LIGHT)
		theme.set_color("font_pressed_color", type, GOLD)
		theme.set_color("font_hover_pressed_color", type, GOLD)
		theme.set_color("font_focus_color", type, GOLD_LIGHT)
		theme.set_color("font_disabled_color", type, DISABLED_TEXT)
		theme.set_color("icon_normal_color", type, PARCH)
		theme.set_color("icon_hover_color", type, GOLD_LIGHT)
		theme.set_constant("h_separation", type, 8)
	# Botón de toggle seleccionado (posturas, pestañas propias): se ve "encendido".
	theme.set_stylebox("pressed", "Button", _box(Color("4a2f17"), GOLD_LIGHT, 2, 3, 16, 8, 2))
	theme.set_stylebox("hover_pressed", "Button", _box(Color("553619"), GOLD_LIGHT, 2, 3, 16, 8, 2))

	# Acción principal (Comenzar, Atacar, Avanzar turno): carmesí con borde dorado.
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", _box(CRIMSON, GOLD, 2, 3, 18, 9, 4))
	theme.set_stylebox("hover", "PrimaryButton", _box(CRIMSON_HI, GOLD_LIGHT, 2, 3, 18, 9, 5))
	theme.set_stylebox("pressed", "PrimaryButton", _box(Color("5c1914"), GOLD_LIGHT, 2, 3, 18, 9, 1))
	theme.set_stylebox("disabled", "PrimaryButton", _box(Color(CRIMSON, 0.4), BRONZE_DIM, 2, 3, 18, 9))
	theme.set_font_size("font_size", "PrimaryButton", 16)

	# Botón discreto (Volver, Cerrar): sin caja hasta pasar el ratón.
	theme.set_type_variation("FlatButton", "Button")
	theme.set_stylebox("normal", "FlatButton", _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 3, 12, 6))
	theme.set_stylebox("hover", "FlatButton", _box(Color(1, 1, 1, 0.06), BRONZE, 1, 3, 12, 6))
	theme.set_stylebox("pressed", "FlatButton", _box(Color(0, 0, 0, 0.2), GOLD, 1, 3, 12, 6))
	theme.set_stylebox("disabled", "FlatButton", _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 3, 12, 6))
	theme.set_color("font_color", "FlatButton", PARCH_DIM)

	# Botón grande del menú principal.
	theme.set_type_variation("MenuButtonLarge", "Button")
	theme.set_font_size("font_size", "MenuButtonLarge", 18)
	theme.set_stylebox("normal", "MenuButtonLarge", _box(Color(WOOD, 0.85), BRONZE, 2, 3, 24, 11, 4))
	theme.set_stylebox("hover", "MenuButtonLarge", _box(Color(WOOD_HI, 0.95), GOLD, 2, 3, 30, 11, 6))
	theme.set_stylebox("pressed", "MenuButtonLarge", _box(WOOD_LO, GOLD_LIGHT, 2, 3, 30, 11, 1))
	theme.set_stylebox("disabled", "MenuButtonLarge", _box(Color(WOOD, 0.45), BRONZE_DIM, 2, 3, 24, 11))

	# Casilla y deslizadores de opciones.
	for type in ["CheckBox", "CheckButton"]:
		theme.set_icon("checked", type, _icon(22, _check_box(true)))
		theme.set_icon("unchecked", type, _icon(22, _check_box(false)))
		theme.set_icon("checked_disabled", type, _icon(22, _check_box(true)))
		theme.set_icon("unchecked_disabled", type, _icon(22, _check_box(false)))
		theme.set_stylebox("normal", type, _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 3, 4, 4))
		theme.set_stylebox("hover", type, _box(Color(1, 1, 1, 0.05), Color.TRANSPARENT, 0, 3, 4, 4))
		theme.set_stylebox("pressed", type, _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 3, 4, 4))
		theme.set_stylebox("hover_pressed", type, _box(Color(1, 1, 1, 0.05), Color.TRANSPARENT, 0, 3, 4, 4))
		theme.set_font("font", type, head)
		theme.set_font_size("font_size", type, 15)
		theme.set_color("font_color", type, PARCH)
		theme.set_color("font_hover_color", type, GOLD_LIGHT)
		theme.set_color("font_pressed_color", type, PARCH)
		theme.set_color("font_hover_pressed_color", type, GOLD_LIGHT)

func _labels(body: Font, body_bold: Font, head: Font, title: Font) -> void:
	theme.set_color("font_color", "Label", PARCH)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_constant("line_spacing", "Label", 2)

	var variations := {
		# nombre: [fuente, tamaño, color]
		"TitleLabel": [title, 38, GOLD_LIGHT],
		"HeaderLabel": [head, 24, GOLD],
		"SubheaderLabel": [head, 16, GOLD],
		"MutedLabel": [body, 16, PARCH_DIM],
		"BodyBoldLabel": [body_bold, 18, PARCH],
		"StatLabel": [body_bold, 20, GOLD_LIGHT],
	}
	for v in variations:
		theme.set_type_variation(v, "Label")
		theme.set_font("font", v, variations[v][0])
		theme.set_font_size("font_size", v, variations[v][1])
		theme.set_color("font_color", v, variations[v][2])
	theme.set_color("font_outline_color", "TitleLabel", Color(0.08, 0.05, 0.02, 0.9))
	theme.set_constant("outline_size", "TitleLabel", 6)
	theme.set_constant("shadow_offset_y", "TitleLabel", 3)

	# Texto oscuro sobre pergamino.
	theme.set_type_variation("InkLabel", "Label")
	theme.set_color("font_color", "InkLabel", INK_TEXT)
	theme.set_color("font_shadow_color", "InkLabel", Color.TRANSPARENT)
	theme.set_type_variation("InkHeaderLabel", "Label")
	theme.set_font("font", "InkHeaderLabel", head)
	theme.set_font_size("font_size", "InkHeaderLabel", 18)
	theme.set_color("font_color", "InkHeaderLabel", Color("5a2a14"))
	theme.set_color("font_shadow_color", "InkHeaderLabel", Color.TRANSPARENT)

func _panels() -> void:
	var panel := _box(PANEL, BRONZE, 2, 4, 18, 14, 10)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)

	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", _box(CARD, BRONZE_DIM, 1, 3, 14, 10, 0))

	theme.set_type_variation("HighlightPanel", "PanelContainer")
	theme.set_stylebox("panel", "HighlightPanel", _box(Color(0.24, 0.16, 0.08, 0.92), GOLD, 2, 3, 14, 10, 6))

	theme.set_type_variation("BarPanel", "PanelContainer")   # barras superiores (HUD)
	var bar := _box(Color(0.07, 0.05, 0.035, 0.9), BRONZE, 0, 0, 18, 8, 8)
	bar.border_width_bottom = 2
	theme.set_stylebox("panel", "BarPanel", bar)

	theme.set_type_variation("ParchmentPanel", "PanelContainer")
	theme.set_stylebox("panel", "ParchmentPanel", _box(Color("e6d5b0"), Color("8a6a3a"), 2, 3, 18, 14, 8))

func _inputs(body: Font) -> void:
	var field := _box(Color("0f0a07"), BRONZE, 1, 3, 10, 6)
	var field_focus := _box(Color("140e09"), GOLD, 2, 3, 10, 6)
	for type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, field)
		theme.set_stylebox("focus", type, field_focus)
		theme.set_stylebox("read_only", type, _box(Color("0f0a07", 0.6), BRONZE_DIM, 1, 3, 10, 6))
		theme.set_font("font", type, body)
		theme.set_font_size("font_size", type, 18)
		theme.set_color("font_color", type, PARCH)
		theme.set_color("font_placeholder_color", type, Color(PARCH_DIM, 0.6))
		theme.set_color("caret_color", type, GOLD_LIGHT)
		theme.set_color("selection_color", type, Color(GOLD, 0.35))

func _bars_and_sliders(head: Font) -> void:
	theme.set_stylebox("background", "ProgressBar", _box(Color("0d0906"), BRONZE_DIM, 1, 3, 0, 0))
	theme.set_stylebox("fill", "ProgressBar", _box(CRIMSON_HI, Color.TRANSPARENT, 0, 3, 0, 0))
	theme.set_font("font", "ProgressBar", head)
	theme.set_font_size("font_size", "ProgressBar", 12)
	theme.set_color("font_color", "ProgressBar", PARCH)
	theme.set_color("font_outline_color", "ProgressBar", Color(0, 0, 0, 0.9))
	theme.set_constant("outline_size", "ProgressBar", 4)

	var track := _box(Color("0d0906"), BRONZE_DIM, 1, 4, 0, 3)
	var filled := _box(Color(GOLD, 0.75), Color.TRANSPARENT, 0, 4, 0, 3)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(GOLD, Color.TRANSPARENT, 0, 4, 0, 3))
	theme.set_icon("grabber", "HSlider", _icon(20, _circle(GOLD_LIGHT, BRONZE)))
	theme.set_icon("grabber_highlight", "HSlider", _icon(20, _circle(Color.WHITE, GOLD)))

	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, _box(Color(0, 0, 0, 0.25), Color.TRANSPARENT, 0, 4, 4, 4))
		theme.set_stylebox("grabber", type, _box(BRONZE, Color.TRANSPARENT, 0, 4, 4, 4))
		theme.set_stylebox("grabber_highlight", type, _box(GOLD, Color.TRANSPARENT, 0, 4, 4, 4))
		theme.set_stylebox("grabber_pressed", type, _box(GOLD_LIGHT, Color.TRANSPARENT, 0, 4, 4, 4))

	var sep := StyleBoxLine.new()
	sep.color = Color(BRONZE, 0.7)
	sep.thickness = 1
	theme.set_stylebox("separator", "HSeparator", sep)
	theme.set_constant("separation", "HSeparator", 12)
	var vsep := StyleBoxLine.new()
	vsep.color = Color(BRONZE, 0.7)
	vsep.thickness = 1
	vsep.vertical = true
	theme.set_stylebox("separator", "VSeparator", vsep)

func _tabs_and_popups(body: Font, head: Font) -> void:
	var tab_sel := _box(PANEL, GOLD, 0, 0, 14, 7)
	tab_sel.border_width_top = 3
	tab_sel.corner_radius_top_left = 3
	tab_sel.corner_radius_top_right = 3
	var tab_un := _box(Color(WOOD_LO, 0.85), BRONZE_DIM, 0, 0, 14, 7)
	tab_un.border_width_top = 1
	var tab_hover := _box(WOOD_HI, BRONZE, 0, 0, 14, 7)
	tab_hover.border_width_top = 2
	for type in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", type, tab_sel)
		theme.set_stylebox("tab_unselected", type, tab_un)
		theme.set_stylebox("tab_hovered", type, tab_hover)
		theme.set_stylebox("tab_disabled", type, tab_un)
		theme.set_font("font", type, head)
		theme.set_font_size("font_size", type, 14)
		theme.set_color("font_selected_color", type, GOLD_LIGHT)
		theme.set_color("font_unselected_color", type, PARCH_DIM)
		theme.set_color("font_hovered_color", type, PARCH)
	theme.set_stylebox("panel", "TabContainer", _box(PANEL, BRONZE, 2, 3, 16, 14, 8))

	var popup := _box(Color("17100b"), BRONZE, 2, 3, 6, 6, 8)
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", _box(Color(GOLD, 0.22), Color.TRANSPARENT, 0, 2, 8, 4))
	theme.set_font("font", "PopupMenu", body)
	theme.set_font_size("font_size", "PopupMenu", 17)
	theme.set_color("font_color", "PopupMenu", PARCH)
	theme.set_color("font_hover_color", "PopupMenu", GOLD_LIGHT)
	theme.set_color("font_disabled_color", "PopupMenu", DISABLED_TEXT)
	theme.set_constant("v_separation", "PopupMenu", 6)

	theme.set_stylebox("panel", "TooltipPanel", _box(Color("120c08", 0.97), GOLD, 1, 3, 10, 7, 6))
	theme.set_font("font", "TooltipLabel", body)
	theme.set_font_size("font_size", "TooltipLabel", 16)
	theme.set_color("font_color", "TooltipLabel", PARCH)

func _misc(body: Font, body_bold: Font) -> void:
	theme.set_font("normal_font", "RichTextLabel", body)
	theme.set_font("bold_font", "RichTextLabel", body_bold)
	theme.set_font_size("normal_font_size", "RichTextLabel", 18)
	theme.set_font_size("bold_font_size", "RichTextLabel", 18)
	theme.set_color("default_color", "RichTextLabel", PARCH)
	theme.set_stylebox("panel", "ItemList", _box(Color("0f0a07"), BRONZE, 1, 3, 6, 6))
	theme.set_color("font_color", "ItemList", PARCH)
	theme.set_stylebox("selected", "ItemList", _box(Color(GOLD, 0.25), GOLD, 1, 2, 4, 2))
	theme.set_stylebox("selected_focus", "ItemList", _box(Color(GOLD, 0.3), GOLD_LIGHT, 1, 2, 4, 2))
	theme.set_stylebox("hovered", "ItemList", _box(Color(1, 1, 1, 0.05), Color.TRANSPARENT, 0, 2, 4, 2))
