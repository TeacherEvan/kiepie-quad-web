extends RefCounted
## Central visual tokens and style helpers for the Kiepie Quad Control UI.
## Called by scene builders (build time) and menu scripts (runtime). This module
## holds no state and touches no game logic - visual skin only.
## All colours are sRGB-in-gamut; contrast on BG is >= 8:1 for every text token.

const BG := Color(0.035, 0.045, 0.065, 1.0)          # #090B10
const SURFACE := Color(0.075, 0.085, 0.105, 0.82)    # chip / panel
const SURFACE_BUTTON := Color(0.090, 0.106, 0.137, 0.94)
const SURFACE_HOVER := Color(0.122, 0.145, 0.184, 0.97)
const SURFACE_PRESSED := Color(0.055, 0.063, 0.082, 0.98)
const SURFACE_DISABLED := Color(0.045, 0.052, 0.068, 0.75)

const TEXT := Color(0.910, 0.929, 0.969, 1.0)        # #E8EDF7  16.8:1
const MUTED := Color(0.620, 0.678, 0.780, 1.0)       # #9EADC7   8.7:1
const GOLD := Color(1.0, 0.820, 0.420, 1.0)          # #FFD16B  13.7:1
const INFO := Color(0.722, 0.820, 0.961, 1.0)        # #B8D1F5  12.6:1
const OK := Color(0.553, 0.949, 0.702, 1.0)          # #8DF2B3  14.5:1
const WARN := Color(1.0, 0.720, 0.340, 1.0)
const DANGER := Color(1.0, 0.518, 0.400, 1.0)        # #FF8466   8.2:1
const ACCENT := Color(1.0, 0.550, 0.160, 1.0)

const STROKE := Color(1.0, 1.0, 1.0, 0.09)
const STROKE_STRONG := Color(0.42, 0.50, 0.62, 0.55)
const SHADOW := Color(0.0, 0.0, 0.0, 0.55)


## Tactile surface: hairline top edge, heavier bottom edge, rounded + AA, drop shadow.
static func chip(bg: Color = SURFACE, border: Color = STROKE, radius: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_top = 1
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_bottom = 2
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.corner_detail = 8
	s.anti_aliasing = true
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 7.0
	s.content_margin_bottom = 7.0
	s.shadow_color = SHADOW
	s.shadow_size = 10
	s.shadow_offset = Vector2(0.0, 3.0)
	return s


static func button_style(bg: Color, border: Color, corner: int = 13) -> StyleBoxFlat:
	return chip(bg, border, corner)


## Rounded track that matches a rounded bar_fill (no square block in a pill).
static func bar_track() -> StyleBoxFlat:
	var s := chip(Color(0.02, 0.03, 0.04, 0.85), Color(1.0, 1.0, 1.0, 0.07), 8)
	s.content_margin_left = 2.0
	s.content_margin_right = 2.0
	s.content_margin_top = 2.0
	s.content_margin_bottom = 2.0
	s.shadow_size = 4
	s.shadow_offset = Vector2(0.0, 2.0)
	return s


static func bar_fill(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.corner_detail = 8
	s.anti_aliasing = true
	return s


## Five engine states (Button/OptionButton/CheckBox/ColorPickerButton share them).
static func style_button(btn: Button, accent: Color, font_size: int = 16, min_h: float = 52.0) -> void:
	btn.add_theme_stylebox_override("normal", button_style(SURFACE_BUTTON, STROKE_STRONG))
	btn.add_theme_stylebox_override("hover", button_style(SURFACE_HOVER, accent))
	btn.add_theme_stylebox_override("pressed", button_style(SURFACE_PRESSED, GOLD))
	btn.add_theme_stylebox_override("disabled", button_style(SURFACE_DISABLED, Color(0.30, 0.30, 0.30, 0.35)))
	btn.add_theme_stylebox_override("focus", button_style(SURFACE_BUTTON, Color(1.0, 0.75, 0.30, 0.95)))
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", GOLD)
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.93, 0.62, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.52, 0.52, 0.52, 0.85))
	btn.add_theme_color_override("font_focus_color", GOLD)
	btn.add_theme_font_size_override("font_size", font_size)
	if min_h > 0.0:
		var ms := btn.custom_minimum_size
		ms.y = maxf(ms.y, min_h)
		btn.custom_minimum_size = ms


## HSlider theme items are: slider / grabber_area / grabber_area_highlight,
## plus the `grabber` and `grabber_highlight` ICONS. A flat StyleBoxFlat has no
## intrinsic height, so the track needs content margins or it collapses to a dot.
static func style_slider(s: Slider, min_h: float = 48.0) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.06, 0.08, 0.11, 0.95)
	track.corner_radius_top_left = 7
	track.corner_radius_top_right = 7
	track.corner_radius_bottom_left = 7
	track.corner_radius_bottom_right = 7
	track.anti_aliasing = true
	track.content_margin_top = 5.0
	track.content_margin_bottom = 5.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.55, 0.12, 0.96)
	fill.corner_radius_top_left = 7
	fill.corner_radius_top_right = 7
	fill.corner_radius_bottom_left = 7
	fill.corner_radius_bottom_right = 7
	fill.anti_aliasing = true
	fill.content_margin_top = 5.0
	fill.content_margin_bottom = 5.0
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = Color(1.0, 0.72, 0.25, 1.0)
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	var grabber := slider_grabber_texture()
	s.add_theme_icon_override("grabber", grabber)
	s.add_theme_icon_override("grabber_highlight", slider_grabber_texture(true))
	if min_h > 0.0:
		var ms := s.custom_minimum_size
		ms.y = maxf(ms.y, min_h)
		s.custom_minimum_size = ms


static var _grabber_tex: ImageTexture
static var _grabber_tex_hi: ImageTexture

## Small circular grabber icons, generated once at runtime (no packed textures).
static func slider_grabber_texture(highlight: bool = false) -> ImageTexture:
	if highlight and _grabber_tex_hi != null:
		return _grabber_tex_hi
	if not highlight and _grabber_tex != null:
		return _grabber_tex
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := Color(0.30, 0.18, 0.03, 1.0) if not highlight else Color(1.0, 0.95, 0.72, 1.0)
	var core := Color(1.0, 0.78, 0.30, 1.0) if not highlight else Color(1.0, 0.92, 0.55, 1.0)
	for y in range(18):
		for x in range(18):
			var d := Vector2(float(x) - 8.5, float(y) - 8.5).length()
			if d <= 7.5:
				img.set_pixel(x, y, core if d < 5.5 else edge)
	var tex := ImageTexture.create_from_image(img)
	if highlight:
		_grabber_tex_hi = tex
	else:
		_grabber_tex = tex
	return tex


## LineEdit theme items are: normal, focus, read_only (no "disabled" item).
static func style_line(le: LineEdit, min_h: float = 48.0) -> void:
	var normal := chip(Color(0.045, 0.055, 0.075, 0.95), STROKE_STRONG, 10)
	normal.content_margin_left = 12.0
	normal.content_margin_right = 12.0
	var focus := chip(Color(0.055, 0.067, 0.090, 0.98), GOLD, 10)
	focus.content_margin_left = 12.0
	focus.content_margin_right = 12.0
	var readonly := chip(Color(0.040, 0.050, 0.065, 0.90), Color(1.0, 1.0, 1.0, 0.14), 10)
	readonly.content_margin_left = 12.0
	readonly.content_margin_right = 12.0
	le.add_theme_stylebox_override("normal", normal)
	le.add_theme_stylebox_override("focus", focus)
	le.add_theme_stylebox_override("read_only", readonly)
	le.add_theme_color_override("font_color", TEXT)
	le.add_theme_color_override("font_placeholder_color", MUTED)
	le.add_theme_color_override("font_uneditable_color", INFO)
	le.add_theme_color_override("caret_color", GOLD)
	le.add_theme_color_override("selection_color", Color(1.0, 0.75, 0.30, 0.35))
	le.add_theme_font_size_override("font_size", 15)
	if min_h > 0.0:
		var ms := le.custom_minimum_size
		ms.y = maxf(ms.y, min_h)
		le.custom_minimum_size = ms


## Depth for titles/labels without adding nodes or changing layout.
static func title_settings(font_size: int, color: Color) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font_size = font_size
	ls.font_color = color
	ls.shadow_color = Color(0.0, 0.0, 0.0, 0.8)
	ls.shadow_offset = Vector2(0.0, 3.0)
	ls.shadow_size = 6
	return ls


## Runtime-only (call from _ready): ScrollContainer creates its bars lazily.
static func style_scroll(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	var bars: Array = [scroll.get_v_scroll_bar(), scroll.get_h_scroll_bar()]
	for bar in bars:
		if bar == null:
			continue
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0.05, 0.06, 0.08, 0.75)
		track.corner_radius_top_left = 4
		track.corner_radius_top_right = 4
		track.corner_radius_bottom_left = 4
		track.corner_radius_bottom_right = 4
		bar.add_theme_stylebox_override("scroll", track)
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color(0.42, 0.48, 0.58, 0.85)
		grab.corner_radius_top_left = 4
		grab.corner_radius_top_right = 4
		grab.corner_radius_bottom_left = 4
		grab.corner_radius_bottom_right = 4
		bar.add_theme_stylebox_override("grabber", grab)
		var grab_hi := grab.duplicate() as StyleBoxFlat
		grab_hi.bg_color = GOLD
		bar.add_theme_stylebox_override("grabber_highlight", grab_hi)
		bar.add_theme_stylebox_override("grabber_pressed", grab_hi)
