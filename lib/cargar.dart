import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'modelo.dart';

class PictogramaService {
  static final FlutterTts _flutterTts = FlutterTts();
  static Completer<void>? _speechCompleter;

  // Lista en memoria de pictogramas creados por el usuario
  static final List<Pictograma> _pictogramasPersonalizados = [];

  // Lista en memoria de categorías nuevas creadas por el usuario
  static final List<String> _categoriasPersonalizadas = [];

  static final Map<String, List<String>> categoriasArchivos = {
    'SUJETOS': [
      'assets/json/sujetos.json',
      'assets/json/familia.json',
      'assets/json/profesiones.json',
    ],
    'VERBOS': [
      'assets/json/A.json',
      'assets/json/B.json',
      'assets/json/C.json',
      'assets/json/D.json',
      'assets/json/E.json',
      'assets/json/F.json',
      'assets/json/G.json',
      'assets/json/H.json',
      'assets/json/I.json',
      'assets/json/J.json',
      'assets/json/L.json',
      'assets/json/M.json',
      'assets/json/N.json',
      'assets/json/O.json',
      'assets/json/P.json',
      'assets/json/Q.json',
      'assets/json/R.json',
      'assets/json/S.json',
      'assets/json/T.json',
      'assets/json/U.json',
      'assets/json/V.json',
    ],
    'OBJETOS': [
      'assets/json/casa.json',
      'assets/json/dispositivos.json',
      'assets/json/utiles.json',
      'assets/json/comida.json',
      'assets/json/ropa.json',
      'assets/json/instrumentos.json',
      'assets/json/herramientas.json',
      'assets/json/juguetes.json',
      'assets/json/accesorios.json',
      'assets/json/transporte.json',
      'assets/json/animales.json',
      'assets/json/plantas.json',
      'assets/json/letras.json',
      'assets/json/numeros.json',
    ],
    'LUGARES': [
      'assets/json/lugares.json',
    ],
    'EMOCIONES': [
      'assets/json/emociones.json',
      'assets/json/estados.json',
    ],
    'ADJETIVOS': [
      'assets/json/adjetivos.json',
    ],
  };

  static final Set<String> categoriasConSubdivisionesInternas = {
    'CASA',
    'COMIDA',
    'LETRAS',
    'NUMEROS',
    'NÚMEROS',
    'ANIMALES',
    'PLANTAS',
  };

  static Future<void> initTts() async {
    await _flutterTts.setSpeechRate(0.35);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      if (_speechCompleter != null && !_speechCompleter!.isCompleted) {
        _speechCompleter!.complete();
      }
    });

    _flutterTts.setErrorHandler((msg) {
      if (_speechCompleter != null && !_speechCompleter!.isCompleted) {
        _speechCompleter!.complete();
      }
    });

    bool languageAvailable = await _flutterTts.isLanguageAvailable("es-ES");
    if (languageAvailable) {
      await _flutterTts.setLanguage("es-ES");
    } else {
      await _flutterTts.setLanguage("es-MX");
    }

    // Cargar datos persistentes guardados por el usuario
    await cargarCategoriasPersonalizadasPersistentes();
    await cargarPictogramasPersonalizadosPersistentes();
  }

  // OBTENER LISTA DE PICTOGRAMAS PERSONALIZADOS
  static List<Pictograma> obtenerPictogramasPersonalizados() {
    return List.unmodifiable(_pictogramasPersonalizados);
  }

  // ELIMINAR PICTOGRAMA PERSONALIZADO
  static Future<void> eliminarPictogramaPersonalizado(String id) async {
    _pictogramasPersonalizados.removeWhere((p) => p.id == id);
    await guardarPictogramasPersonalizadosPersistentes();
  }

  // PERSISTENCIA DE CATEGORÍAS NUEVAS CREADAS POR EL USUARIO
  static Future<void> agregarCategoriaNueva(String nuevaCategoria) async {
    final catUpper = nuevaCategoria.trim().toUpperCase();
    if (catUpper.isNotEmpty &&
        !categoriasArchivos.containsKey(catUpper) &&
        !_categoriasPersonalizadas.contains(catUpper)) {
      _categoriasPersonalizadas.add(catUpper);
      categoriasArchivos[catUpper] = []; // Registrar la categoría en el mapa de archivos
      await guardarCategoriasPersonalizadasPersistentes();
    }
  }

  static Future<void> cargarCategoriasPersonalizadasPersistentes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? guardadas = prefs.getStringList('categorias_custom');
      if (guardadas != null) {
        for (var cat in guardadas) {
          final catUpper = cat.toUpperCase();
          if (!categoriasArchivos.containsKey(catUpper)) {
            categoriasArchivos[catUpper] = [];
            if (!_categoriasPersonalizadas.contains(catUpper)) {
              _categoriasPersonalizadas.add(catUpper);
            }
          }
        }
      }
    } catch (e) {
      print("⚠️ Error al cargar categorías personalizadas: $e");
    }
  }

  static Future<void> guardarCategoriasPersonalizadasPersistentes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('categorias_custom', _categoriasPersonalizadas);
    } catch (e) {
      print("⚠️ Error al guardar categorías personalizadas: $e");
    }
  }

  // PERSISTENCIA DE PICTOGRAMAS CREADOS POR EL USUARIO
  static Future<void> cargarPictogramasPersonalizadosPersistentes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? jsonList = prefs.getStringList('pictogramas_custom');
      if (jsonList != null) {
        _pictogramasPersonalizados.clear();
        for (var str in jsonList) {
          final Map<String, dynamic> map = json.decode(str);
          _pictogramasPersonalizados.add(Pictograma.fromJson(map, subcategoriaDefecto: 'GENERAL'));
        }
      }
    } catch (e) {
      print("⚠️ Error al cargar pictogramas personalizados: $e");
    }
  }

  static Future<void> guardarPictogramasPersonalizadosPersistentes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> jsonList = _pictogramasPersonalizados
          .map((p) => json.encode(p.toJson()))
          .toList();
      await prefs.setStringList('pictogramas_custom', jsonList);
    } catch (e) {
      print("⚠️ Error al guardar pictogramas personalizados: $e");
    }
  }

  static Future<void> agregarPictogramaPersonalizado(String categoria, Pictograma p) async {
    _pictogramasPersonalizados.add(p);
    await guardarPictogramasPersonalizadosPersistentes();
  }

  static Future<void> reproducirTexto(String texto) async {
    await _flutterTts.stop();
    _speechCompleter = Completer<void>();
    final textoParaVoz = texto.trim().toLowerCase();
    await _flutterTts.speak(textoParaVoz);
    return _speechCompleter!.future;
  }

  static Future<void> detenerVoz() async {
    await _flutterTts.stop();
    if (_speechCompleter != null && !_speechCompleter!.isCompleted) {
      _speechCompleter!.complete();
    }
  }

  static Future<List<Pictograma>> cargarPorArchivoJson(String rutaArchivo) async {
    try {
      final jsonString = await rootBundle.loadString(rutaArchivo);
      final List<dynamic> jsonList = json.decode(jsonString);

      String nombreSubcategoriaDefecto = rutaArchivo
          .split('/')
          .last
          .replaceAll('.json', '')
          .replaceAll('_', ' ')
          .toUpperCase();

      List<Pictograma> lista = jsonList
          .map((item) => Pictograma.fromJson(
        item,
        subcategoriaDefecto: nombreSubcategoriaDefecto,
      ))
          .toList();

      // INCLUIR PICTOGRAMAS DEL USUARIO EN ESTA SUBCATEGORÍA
      final deUsuario = _pictogramasPersonalizados.where(
            (p) => p.subcategoria.toUpperCase().trim() == nombreSubcategoriaDefecto.toUpperCase().trim(),
      );
      lista.addAll(deUsuario);

      lista.sort((a, b) => a.etiqueta.compareTo(b.etiqueta));
      return lista;
    } catch (e) {
      print("⚠️ Error al cargar $rutaArchivo: $e");
      return [];
    }
  }

  static Future<List<Pictograma>> cargarPorCategoriaPrincipal(String categoria) async {
    final catUpper = categoria.toUpperCase().trim();
    final archivos = categoriasArchivos[catUpper] ?? categoriasArchivos[categoria];
    List<Pictograma> resultado = [];

    if (archivos != null && archivos.isNotEmpty) {
      for (String archivo in archivos) {
        final lista = await cargarPorArchivoJson(archivo);
        resultado.addAll(lista);
      }
    }

    // INCLUIR PICTOGRAMAS DEL USUARIO DE ESTA CATEGORÍA O SUBCATEGORÍA
    final deUsuario = _pictogramasPersonalizados.where(
          (p) => p.tipoPalabra.toUpperCase().trim() == catUpper ||
          p.subcategoria.toUpperCase().trim() == catUpper,
    );

    for (var customItem in deUsuario) {
      if (!resultado.any((element) => element.id == customItem.id)) {
        resultado.add(customItem);
      }
    }

    resultado.sort((a, b) => a.etiqueta.compareTo(b.etiqueta));
    return resultado;
  }

  static Future<List<Pictograma>> cargarTodos() async {
    List<Pictograma> todos = [];
    for (String categoria in categoriasArchivos.keys) {
      final items = await cargarPorCategoriaPrincipal(categoria);
      todos.addAll(items);
    }

    todos.sort((a, b) => a.etiqueta.compareTo(b.etiqueta));
    return todos;
  }

  static Map<String, List<Pictograma>> obtenerSubdivisionesSiAplica(
      List<Pictograma> lista,
      String tituloBloque,
      ) {
    final tituloNorm = tituloBloque.toUpperCase().trim();

    if (!categoriasConSubdivisionesInternas.contains(tituloNorm)) {
      return {};
    }

    Map<String, List<Pictograma>> agrupados = {};
    for (var p in lista) {
      String sub = p.subcategoria.toUpperCase().trim();
      if (sub.isEmpty) sub = 'GENERAL';
      agrupados.putIfAbsent(sub, () => []).add(p);
    }

    if (agrupados.keys.length <= 1) {
      return {};
    }

    for (var key in agrupados.keys) {
      agrupados[key]!.sort((a, b) => a.etiqueta.compareTo(b.etiqueta));
    }

    return agrupados;
  }

  static String _detectarPersonaGramatical(List<Pictograma> contexto) {
    if (contexto.isEmpty) return 'yo';

    final sujetos = contexto.where(
          (p) =>
      p.tipoPalabra.toLowerCase().contains('sujeto') ||
          p.tipoPalabra.toLowerCase().contains('pronombre') ||
          p.subcategoria.contains('SUJETOS') ||
          p.subcategoria.contains('FAMILIA') ||
          p.subcategoria.contains('PROFESIONES'),
    );

    if (sujetos.isEmpty) return 'yo';

    final ultimoSujeto = sujetos.last;
    final etiqueta = ultimoSujeto.etiqueta.toLowerCase().trim();

    if (etiqueta == 'yo') return 'yo';
    if (etiqueta == 'tú' || etiqueta == 'tu') return 'tu';
    if (etiqueta == 'él' || etiqueta == 'el' || etiqueta == 'ella' || etiqueta == 'usted') {
      return 'el_ella_usted';
    }
    if (etiqueta == 'nosotros' || etiqueta == 'nosotras') return 'nosotros';
    if (etiqueta == 'ellos' || etiqueta == 'ellas' || etiqueta == 'ustedes') {
      return 'ellos_ellas_ustedes';
    }

    return 'el_ella_usted';
  }

  static String obtenerVerboConjugado(
      Pictograma verbo,
      List<Pictograma> contexto, {
        String tiempo = 'presente',
      }) {
    if (verbo.jsonRaw == null || !verbo.jsonRaw!.containsKey('conjugaciones')) {
      return verbo.etiqueta;
    }

    try {
      final conjugaciones = verbo.jsonRaw!['conjugaciones'];
      final tiempoNorm = tiempo.toLowerCase().trim();
      final personaKey = _detectarPersonaGramatical(contexto);

      if (conjugaciones is Map<String, dynamic> && conjugaciones.containsKey(tiempoNorm)) {
        final mapaTiempo = conjugaciones[tiempoNorm];
        if (mapaTiempo is Map<String, dynamic> && mapaTiempo.containsKey(personaKey)) {
          final verboConjugado = mapaTiempo[personaKey]?.toString();
          if (verboConjugado != null && verboConjugado.isNotEmpty) {
            return verboConjugado;
          }
        }
      }
    } catch (e) {
      print("⚠️ Error al obtener conjugación del verbo ${verbo.etiqueta}: $e");
    }

    return verbo.etiqueta;
  }
}