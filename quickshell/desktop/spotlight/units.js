.pragma library

// Unit conversion for the spotlight bar: "26.5 inch to cm", "72 f to c",
// "100 km/h in mph", "3 gb to mib".
//
// Everything is stored as an affine map onto a per-dimension base unit:
//   base = value * f + o        value = (base - o) / f
// The offset only matters for temperature (C/F/K/R); every other unit leaves it
// at 0, so one code path covers both cases.

function _u(dim, f, o) { return { dim: dim, f: f, o: o || 0 } }

// Spread a single definition over several spellings.
function _add(table, names, def) {
    for (var i = 0; i < names.length; i++) table[names[i]] = def
}

var TABLE = (function () {
    var t = {}

    // ── length (base: metre) ────────────────────────────────────────────────
    _add(t, ["nm", "nanometre", "nanometer"],              _u("length", 1e-9))
    _add(t, ["um", "micrometre", "micrometer", "micron"],  _u("length", 1e-6))
    _add(t, ["mm", "millimetre", "millimeter"],            _u("length", 1e-3))
    _add(t, ["cm", "centimetre", "centimeter"],            _u("length", 1e-2))
    _add(t, ["dm", "decimetre", "decimeter"],              _u("length", 0.1))
    _add(t, ["m", "metre", "meter"],                       _u("length", 1))
    _add(t, ["km", "kilometre", "kilometer"],              _u("length", 1e3))
    _add(t, ["in", "inch", "inche", "\""],                 _u("length", 0.0254))
    _add(t, ["ft", "foot", "feet", "'"],                   _u("length", 0.3048))
    _add(t, ["yd", "yard"],                                _u("length", 0.9144))
    _add(t, ["mi", "mile"],                                _u("length", 1609.344))
    _add(t, ["nmi", "nauticalmile"],                       _u("length", 1852))
    _add(t, ["mil", "thou"],                               _u("length", 2.54e-5))
    _add(t, ["furlong"],                                   _u("length", 201.168))
    _add(t, ["fathom"],                                    _u("length", 1.8288))
    _add(t, ["angstrom"],                                  _u("length", 1e-10))
    _add(t, ["ly", "lightyear"],                           _u("length", 9.4607304725808e15))
    _add(t, ["au", "astronomicalunit"],                    _u("length", 1.495978707e11))
    _add(t, ["pc", "parsec"],                              _u("length", 3.0856775814913673e16))

    // ── mass (base: kilogram) ───────────────────────────────────────────────
    _add(t, ["ug", "microgram"],                           _u("mass", 1e-9))
    _add(t, ["mg", "milligram"],                           _u("mass", 1e-6))
    _add(t, ["g", "gram", "gramme"],                       _u("mass", 1e-3))
    _add(t, ["kg", "kilogram", "kilo"],                    _u("mass", 1))
    _add(t, ["t", "tonne", "metricton"],                   _u("mass", 1000))
    _add(t, ["oz", "ounce"],                               _u("mass", 0.028349523125))
    _add(t, ["lb", "lbs", "pound"],                        _u("mass", 0.45359237))
    _add(t, ["st", "stone"],                               _u("mass", 6.35029318))
    _add(t, ["grain"],                                     _u("mass", 6.479891e-5))
    _add(t, ["carat", "ct"],                               _u("mass", 2e-4))
    _add(t, ["shortton", "uston", "ton"],                  _u("mass", 907.18474))
    _add(t, ["longton", "ukton"],                          _u("mass", 1016.0469088))

    // ── temperature (base: kelvin) ──────────────────────────────────────────
    // The only affine family. F: K = F*5/9 + (273.15 - 32*5/9).
    _add(t, ["c", "celsius", "centigrade"],                _u("temp", 1, 273.15))
    _add(t, ["f", "fahrenheit"],                           _u("temp", 5 / 9, 273.15 - 32 * 5 / 9))
    _add(t, ["k", "kelvin"],                               _u("temp", 1, 0))
    _add(t, ["r", "rankine"],                              _u("temp", 5 / 9, 0))

    // ── volume (base: litre) ────────────────────────────────────────────────
    _add(t, ["ml", "millilitre", "milliliter"],            _u("volume", 1e-3))
    _add(t, ["cl", "centilitre", "centiliter"],            _u("volume", 1e-2))
    _add(t, ["dl", "decilitre", "deciliter"],              _u("volume", 0.1))
    _add(t, ["l", "litre", "liter"],                       _u("volume", 1))
    _add(t, ["m3", "cubicmetre", "cubicmeter"],            _u("volume", 1000))
    _add(t, ["cm3", "cc"],                                 _u("volume", 1e-3))
    _add(t, ["gal", "gallon", "usgal"],                    _u("volume", 3.785411784))
    _add(t, ["impgal", "ukgal", "imperialgallon"],         _u("volume", 4.54609))
    _add(t, ["qt", "quart"],                               _u("volume", 0.946352946))
    _add(t, ["pt", "pint"],                                _u("volume", 0.473176473))
    _add(t, ["cup"],                                       _u("volume", 0.2365882365))
    _add(t, ["floz", "fluidounce"],                        _u("volume", 0.0295735295625))
    _add(t, ["tbsp", "tablespoon"],                        _u("volume", 0.01478676478125))
    _add(t, ["tsp", "teaspoon"],                           _u("volume", 0.00492892159375))
    _add(t, ["bbl", "barrel"],                             _u("volume", 158.987294928))

    // ── area (base: square metre) ───────────────────────────────────────────
    _add(t, ["mm2"],                                       _u("area", 1e-6))
    _add(t, ["cm2"],                                       _u("area", 1e-4))
    _add(t, ["m2", "sqm", "squaremetre", "squaremeter"],   _u("area", 1))
    _add(t, ["km2", "sqkm"],                               _u("area", 1e6))
    _add(t, ["in2", "sqin"],                               _u("area", 6.4516e-4))
    _add(t, ["ft2", "sqft"],                               _u("area", 0.09290304))
    _add(t, ["yd2", "sqyd"],                               _u("area", 0.83612736))
    _add(t, ["acre"],                                      _u("area", 4046.8564224))
    _add(t, ["ha", "hectare"],                             _u("area", 1e4))
    _add(t, ["mi2", "sqmi"],                               _u("area", 2589988.110336))
    _add(t, ["pyeong", "py"],                              _u("area", 400 / 121))

    // ── time (base: second) ─────────────────────────────────────────────────
    _add(t, ["ns", "nanosecond"],                          _u("time", 1e-9))
    _add(t, ["us", "microsecond"],                         _u("time", 1e-6))
    _add(t, ["ms", "millisecond"],                         _u("time", 1e-3))
    _add(t, ["s", "sec", "second"],                        _u("time", 1))
    _add(t, ["min", "minute"],                             _u("time", 60))
    _add(t, ["h", "hr", "hour"],                           _u("time", 3600))
    _add(t, ["d", "day"],                                  _u("time", 86400))
    _add(t, ["wk", "week"],                                _u("time", 604800))
    _add(t, ["month"],                                     _u("time", 2629800))     // Julian year / 12
    _add(t, ["yr", "year"],                                _u("time", 31557600))    // Julian year

    // ── speed (base: metre/second) ──────────────────────────────────────────
    _add(t, ["m/s", "mps"],                                _u("speed", 1))
    _add(t, ["km/h", "kmh", "kph"],                        _u("speed", 1 / 3.6))
    _add(t, ["mph", "mi/h"],                               _u("speed", 0.44704))
    _add(t, ["ft/s", "fps"],                               _u("speed", 0.3048))
    _add(t, ["kn", "kt", "knot"],                          _u("speed", 0.5144444444444445))
    _add(t, ["mach"],                                      _u("speed", 340.29))

    // ── data (base: byte) ───────────────────────────────────────────────────
    // "b" is deliberately absent — lowercasing makes bit/byte indistinguishable.
    _add(t, ["bit"],                                       _u("data", 0.125))
    _add(t, ["byte"],                                      _u("data", 1))
    _add(t, ["kb", "kilobyte"],                            _u("data", 1e3))
    _add(t, ["mb", "megabyte"],                            _u("data", 1e6))
    _add(t, ["gb", "gigabyte"],                            _u("data", 1e9))
    _add(t, ["tb", "terabyte"],                            _u("data", 1e12))
    _add(t, ["pb", "petabyte"],                            _u("data", 1e15))
    _add(t, ["kib", "kibibyte"],                           _u("data", 1024))
    _add(t, ["mib", "mebibyte"],                           _u("data", 1048576))
    _add(t, ["gib", "gibibyte"],                           _u("data", 1073741824))
    _add(t, ["tib", "tebibyte"],                           _u("data", 1099511627776))

    // ── pressure (base: pascal) ─────────────────────────────────────────────
    _add(t, ["pa", "pascal"],                              _u("pressure", 1))
    _add(t, ["hpa", "hectopascal"],                        _u("pressure", 100))
    _add(t, ["kpa", "kilopascal"],                         _u("pressure", 1e3))
    _add(t, ["mpa", "megapascal"],                         _u("pressure", 1e6))
    _add(t, ["bar"],                                       _u("pressure", 1e5))
    _add(t, ["mbar", "millibar"],                          _u("pressure", 100))
    _add(t, ["psi"],                                       _u("pressure", 6894.757293168))
    _add(t, ["atm", "atmosphere"],                         _u("pressure", 101325))
    _add(t, ["mmhg", "torr"],                              _u("pressure", 133.322387415))

    // ── energy (base: joule) ────────────────────────────────────────────────
    _add(t, ["j", "joule"],                                _u("energy", 1))
    _add(t, ["kj", "kilojoule"],                           _u("energy", 1e3))
    _add(t, ["mj", "megajoule"],                           _u("energy", 1e6))
    _add(t, ["cal", "calorie"],                            _u("energy", 4.184))
    _add(t, ["kcal", "kilocalorie"],                       _u("energy", 4184))
    _add(t, ["wh", "watthour"],                            _u("energy", 3600))
    _add(t, ["kwh", "kilowatthour"],                       _u("energy", 3.6e6))
    _add(t, ["btu"],                                       _u("energy", 1055.05585262))
    _add(t, ["ev", "electronvolt"],                        _u("energy", 1.602176634e-19))

    // ── power (base: watt) ──────────────────────────────────────────────────
    _add(t, ["w", "watt"],                                 _u("power", 1))
    _add(t, ["milliwatt"],                                 _u("power", 1e-3))
    _add(t, ["kw", "kilowatt"],                            _u("power", 1e3))
    _add(t, ["mw", "megawatt"],                            _u("power", 1e6))
    _add(t, ["gw", "gigawatt"],                            _u("power", 1e9))
    _add(t, ["hp", "horsepower"],                          _u("power", 745.6998715822702))
    _add(t, ["ps", "metrichp"],                            _u("power", 735.49875))

    // ── angle (base: degree) ────────────────────────────────────────────────
    _add(t, ["deg", "degree"],                             _u("angle", 1))
    _add(t, ["rad", "radian"],                             _u("angle", 57.29577951308232))
    _add(t, ["grad", "gradian", "gon"],                    _u("angle", 0.9))
    _add(t, ["turn", "rev", "revolution"],                 _u("angle", 360))
    _add(t, ["arcmin"],                                    _u("angle", 1 / 60))
    _add(t, ["arcsec"],                                    _u("angle", 1 / 3600))

    // ── frequency (base: hertz) ─────────────────────────────────────────────
    _add(t, ["hz", "hertz"],                               _u("freq", 1))
    _add(t, ["khz", "kilohertz"],                          _u("freq", 1e3))
    _add(t, ["mhz", "megahertz"],                          _u("freq", 1e6))
    _add(t, ["ghz", "gigahertz"],                          _u("freq", 1e9))
    _add(t, ["rpm"],                                       _u("freq", 1 / 60))

    return t
})()

var DIM_LABEL = {
    length: "length", mass: "mass", temp: "temperature", volume: "volume",
    area: "area", time: "time", speed: "speed", data: "data",
    pressure: "pressure", energy: "energy", power: "power",
    angle: "angle", freq: "frequency"
}

// Fold a written unit onto a table key. Handles case, the degree sign,
// superscripts, micro sign, spacing inside compounds like "km / h", and the
// trailing plural "s" (tried only after the literal spelling misses, so "s"
// for seconds and "ps" for metric horsepower still resolve).
function normalize(tok) {
    if (!tok) return ""
    var s = String(tok).toLowerCase().trim()
    s = s.replace(/°/g, "")
    s = s.replace(/²/g, "2").replace(/³/g, "3")
    s = s.replace(/[µμ]/g, "u")
    s = s.replace(/\s*\/\s*/g, "/")
    s = s.replace(/[\s_]/g, "")
    s = s.replace(/\.+$/, "")
    if (TABLE[s]) return s
    if (s.length > 1 && s.charAt(s.length - 1) === "s" && TABLE[s.slice(0, -1)])
        return s.slice(0, -1)
    return TABLE[s] ? s : ""
}

function lookup(tok) {
    var key = normalize(tok)
    return key ? TABLE[key] : null
}

// Parse "<amount> <from> to|in|into|as <to>".
// Returns { ok, amount, from, to, fromKey, toKey } or { ok:false, reason }.
// `reason` is "mismatch" when both sides are real units of different kinds, so
// the caller can say something better than nothing at all.
function parse(text) {
    if (!text) return { ok: false }
    var m = String(text).trim().match(
        /^([-+]?[\d.,]+(?:[eE][-+]?\d+)?)\s*(.+?)\s+(?:to|in|into|as|->|=>|=|>)\s+(.+?)$/)
    if (!m) return { ok: false }

    var amount = parseFloat(m[1].replace(/,/g, ""))
    if (!isFinite(amount)) return { ok: false }

    var a = lookup(m[2])
    var b = lookup(m[3])
    if (!a || !b) return { ok: false }
    if (a.dim !== b.dim)
        return { ok: false, reason: "mismatch", fromDim: a.dim, toDim: b.dim }

    // `*Raw` keeps the spelling as typed so the result row can echo it back —
    // showing the normalized key instead turns "1 day to hours" into the
    // slightly-wrong-looking "24 hour", and "2.5 m² to ft²" into "ft2".
    return {
        ok: true, amount: amount, from: a, to: b,
        fromKey: normalize(m[2]), toKey: normalize(m[3]),
        fromRaw: m[2].trim(), toRaw: m[3].trim()
    }
}

function convert(amount, from, to) {
    var base = amount * from.f + from.o
    return (base - to.o) / to.f
}

// Round to a readable number of significant digits without printing float noise,
// then strip trailing zeros. Very large/small magnitudes fall back to exponent
// form so "1 ly to mm" stays legible.
function format(v) {
    if (!isFinite(v)) return ""
    if (v === 0) return "0"
    var abs = Math.abs(v)
    if (abs >= 1e15 || abs < 1e-6) return v.toExponential(4).replace(/e([+-])(\d)$/, "e$10$2")

    var decimals
    if (abs >= 1000) decimals = 2
    else if (abs >= 1) decimals = 4
    else decimals = Math.min(10, 4 + Math.ceil(-Math.log(abs) / Math.LN10))

    var s = v.toFixed(decimals)
    if (s.indexOf(".") >= 0) s = s.replace(/0+$/, "").replace(/\.$/, "")
    return s
}

function group(s) {
    var neg = s.charAt(0) === "-"
    if (neg) s = s.slice(1)
    var parts = s.split(".")
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
    return (neg ? "-" : "") + parts.join(".")
}

function dimLabel(d) { return DIM_LABEL[d] || d }
