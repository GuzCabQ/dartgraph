// lib/src/core/glob_match.dart
//
// Coincidencia de patrones glob para filtrar archivos Dart.
// Sin dependencias externas — solo dart:core.
//
// Soporta: '/' al final = directorio prefijo (coincide todo el subárbol);
// '**' = cero o más segmentos de ruta; '*' = comodín dentro de un segmento.
// Sin llaves ni clases de caracteres. Rutas con separador '/', sensible a mayúsculas.
//
// Se mantiene local (no package:glob) para evitar nueva dependencia y mantener
// las reglas de coincidencia pequeñas y completamente testeadas.

/// Verdadero si [path] coincide con [pattern]. Un patrón de directorio sin más
/// (terminado en '/') coincide con cualquier archivo bajo él — incluyendo patrones
/// de directorio que contengan metacaracteres glob (ej. `lib/src/feature/*/presentation/`).
bool globMatch(String pattern, String path) {
  final pat = pattern.replaceAll(r'\', '/');
  final pth = path.replaceAll(r'\', '/');
  final isPrefixDir = pat.endsWith('/');
  // Camino rápido: prefijo de directorio literal (sin metacaracteres glob).
  if (isPrefixDir && !pat.contains('*')) return pth.startsWith(pat);
  final patSegs = (isPrefixDir ? pat.substring(0, pat.length - 1) : pat).split(
    '/',
  );
  return _matchSegments(patSegs, 0, pth.split('/'), 0, prefix: isPrefixDir);
}

bool _matchSegments(
  List<String> pat,
  int pi,
  List<String> path,
  int si, {
  required bool prefix,
}) {
  if (pi == pat.length) {
    // Un patrón de prefijo-dir coincide cuando hay al menos un segmento más
    // debajo (el archivo); un patrón completo requiere consumo exacto.
    return prefix ? si < path.length : si == path.length;
  }
  final seg = pat[pi];
  if (seg == '**') {
    // '**' consume cero o más segmentos completos.
    for (var skip = si; skip <= path.length; skip++) {
      if (_matchSegments(pat, pi + 1, path, skip, prefix: prefix)) return true;
    }
    return false;
  }
  if (si == path.length) return false;
  if (_segMatch(seg, path[si])) {
    return _matchSegments(pat, pi + 1, path, si + 1, prefix: prefix);
  }
  return false;
}

/// Coincidencia de un solo segmento donde '*' es comodín dentro del segmento.
bool _segMatch(String pat, String seg) {
  if (pat == '*') return true;
  if (!pat.contains('*')) return pat == seg;
  final parts = pat.split('*');
  var idx = 0;
  for (var k = 0; k < parts.length; k++) {
    final part = parts[k];
    if (part.isEmpty) continue;
    final found = seg.indexOf(part, idx);
    if (found < 0) return false;
    // Sin '*' al inicio: la primera parte debe anclar al inicio del segmento.
    if (k == 0 && found != 0) {
      return false;
    }
    idx = found + part.length;
  }
  // Sin '*' al final: el patrón debe consumir el segmento hasta el final.
  if (!pat.endsWith('*') && idx != seg.length) return false;
  return true;
}
