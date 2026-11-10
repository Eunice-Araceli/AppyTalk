import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'modelo.dart';
import 'cargar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await PictogramaService.initTts();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  try {
    runApp(const AppyTalkApp());
  } catch (e, stack) {
    print("❌ ERROR CRÍTICO AL INICIAR LA APP: $e");
    print(stack);
  }
}

class AppyTalkApp extends StatelessWidget {
  const AppyTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    const colorFondo = Color(0xFFC8CBD3);
    const colorAppBar = Color(0xFF5A97B8);

    return MaterialApp(
      title: 'APPYTALK',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: colorAppBar,
          onPrimary: Colors.white,
          secondary: colorAppBar,
          surface: colorFondo,
          onSurface: Colors.black,
        ),
        scaffoldBackgroundColor: colorFondo,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: colorAppBar,
          foregroundColor: Colors.white,
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbVisibility: WidgetStateProperty.all(true),
          trackVisibility: WidgetStateProperty.all(true),
          thickness: WidgetStateProperty.all(8.0),
          radius: const Radius.circular(10),
          thumbColor: WidgetStateProperty.all(colorAppBar),
          trackColor: WidgetStateProperty.all(Colors.black12),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _fraseController = TextEditingController();
  final TextEditingController _busquedaController = TextEditingController();
  final FocusNode _fraseFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  final ScrollController _fraseScrollController = ScrollController();

  final List<Pictograma> _frasePictogramas = [];
  final List<String> _frasesFavoritas = [];

  String _busquedaQuery = '';
  String _tiempoVerbalSeleccionado = 'presente';

  final GlobalKey<NavigatorState> _nestedNavigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _indicePalabraLeyendo = -1;
  bool _reproduciendoFrase = false;

  @override
  void initState() {
    super.initState();
    _cargarFavoritosPersistentes();
  }

  @override
  void dispose() {
    _fraseController.dispose();
    _busquedaController.dispose();
    _fraseFocusNode.dispose();
    _keyboardFocusNode.dispose();
    _fraseScrollController.dispose();
    super.dispose();
  }

  Future<void> _cargarFavoritosPersistentes() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? guardados = prefs.getStringList('frases_favoritas');
    if (guardados != null) {
      setState(() {
        _frasesFavoritas.clear();
        _frasesFavoritas.addAll(guardados);
      });
    }
  }

  Future<void> _guardarFavoritosPersistentes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('frases_favoritas', _frasesFavoritas);
  }

  void _agregarAFrase(Pictograma p) {
    setState(() {
      String textoAInsertar = p.etiqueta.toUpperCase();

      final esVerbo = p.tipoPalabra.toLowerCase().contains('verbo') ||
          p.subcategoria.toUpperCase().contains('VERBO') ||
          p.jsonRaw?.containsKey('conjugaciones') == true;

      if (esVerbo) {
        textoAInsertar = PictogramaService.obtenerVerboConjugado(
          p,
          _frasePictogramas,
          tiempo: _tiempoVerbalSeleccionado,
        ).toUpperCase();
      }

      _frasePictogramas.add(p);

      final textoActual = _fraseController.text;
      final selection = _fraseController.selection;
      final start = selection.start >= 0 ? selection.start : textoActual.length;
      final end = selection.end >= 0 ? selection.end : textoActual.length;

      final necesitaEspacioAntes = start > 0 && !textoActual.substring(start - 1, start).endsWith(' ');
      final necesitaEspacioDespues = end < textoActual.length && !textoActual.substring(end, end + 1).startsWith(' ');

      final palabraFormateada = '${necesitaEspacioAntes ? ' ' : ''}$textoAInsertar${necesitaEspacioDespues ? ' ' : ''}';

      final nuevoTexto = textoActual.replaceRange(start, end, palabraFormateada);

      _fraseController.text = nuevoTexto;

      final nuevaPosicionCursor = start + palabraFormateada.length;
      _fraseController.selection = TextSelection.fromPosition(
        TextPosition(offset: nuevaPosicionCursor),
      );

      PictogramaService.reproducirTexto(textoAInsertar);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_fraseScrollController.hasClients) {
        _fraseScrollController.animateTo(
          _fraseScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _borrarPalabraCompleta() {
    final texto = _fraseController.text;
    final selection = _fraseController.selection;

    if (_frasePictogramas.isNotEmpty) {
      _frasePictogramas.removeLast();
    }

    if (selection.start != selection.end && selection.start >= 0) {
      final nuevoTexto = texto.replaceRange(selection.start, selection.end, '');
      _fraseController.text = nuevoTexto;
      _fraseController.selection = TextSelection.fromPosition(
        TextPosition(offset: selection.start),
      );
      return;
    }

    final pos = selection.start;
    if (pos <= 0) return;

    int i = pos - 1;
    while (i >= 0 && texto[i] == ' ') {
      i--;
    }
    while (i >= 0 && texto[i] != ' ') {
      i--;
    }

    final inicioBorrado = i + 1;
    final nuevoTexto = texto.replaceRange(inicioBorrado, pos, '');

    _fraseController.text = nuevoTexto;
    _fraseController.selection = TextSelection.fromPosition(
      TextPosition(offset: inicioBorrado),
    );
  }

  void _limpiarFrase() {
    PictogramaService.detenerVoz();
    setState(() {
      _frasePictogramas.clear();
      _fraseController.clear();
      _reproduciendoFrase = false;
      _indicePalabraLeyendo = -1;
    });
  }

  void _toggleFavorito() {
    final fraseActual = _fraseController.text.trim();
    if (fraseActual.isEmpty) return;

    setState(() {
      if (_frasesFavoritas.contains(fraseActual)) {
        _frasesFavoritas.remove(fraseActual);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Frase eliminada de Favoritos"),
            duration: Duration(seconds: 1),
          ),
        );
      } else {
        _frasesFavoritas.add(fraseActual);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Frase guardada en Favoritos ⭐"),
            duration: Duration(seconds: 1),
          ),
        );
      }
    });

    _guardarFavoritosPersistentes();
  }

  void _cargarFraseFavorita(String frase) {
    setState(() {
      _fraseController.text = frase;
      _fraseController.selection = TextSelection.fromPosition(
        TextPosition(offset: frase.length),
      );
    });
    Navigator.of(context).pop();
    PictogramaService.reproducirTexto(frase);
  }

  void _leerFraseCompleta() async {
    final textoCompleto = _fraseController.text.trim();
    if (textoCompleto.isEmpty) return;

    if (_reproduciendoFrase) {
      await PictogramaService.detenerVoz();
      setState(() {
        _reproduciendoFrase = false;
        _indicePalabraLeyendo = -1;
      });
      return;
    }

    final palabras = textoCompleto.split(RegExp(r'\s+'));

    setState(() {
      _reproduciendoFrase = true;
      _indicePalabraLeyendo = 0;
    });

    for (int i = 0; i < palabras.length; i++) {
      if (!_reproduciendoFrase) break;

      setState(() {
        _indicePalabraLeyendo = i;
      });

      await PictogramaService.reproducirTexto(palabras[i]);
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (mounted) {
      setState(() {
        _reproduciendoFrase = false;
        _indicePalabraLeyendo = -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fraseActual = _fraseController.text.trim();
    final esFavorita = _frasesFavoritas.contains(fraseActual);
    const colorAzul = Color(0xFF5A97B8);

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('APPYTALK'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menú principal',
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),
      endDrawer: Drawer(
        child: Column(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: colorAzul),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.apps_rounded, size: 44, color: Colors.white),
                    SizedBox(height: 8),
                    Text(
                      'MENÚ APPYTALK',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_a_photo, color: colorAzul),
              title: const Text(
                'AGREGAR PICTOGRAMA',
                style: TextStyle(fontWeight: FontWeight.bold, color: colorAzul),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                final bool? guardado = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (context) => const AgregarPictogramaScreen(),
                  ),
                );
                if (guardado == true) {
                  setState(() {});
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: const Text(
                'ELIMINAR PICTOGRAMAS',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                final bool? cambio = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (context) => const EliminarPictogramasScreen(),
                  ),
                );
                if (cambio == true) {
                  setState(() {});
                }
              },
            ),
            const Divider(height: 12, thickness: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 16.0, top: 8.0, bottom: 4.0),
                    child: Text(
                      'FAVORITOS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: colorAzul,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  if (_frasesFavoritas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: Text(
                        'No hay frases guardadas.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    )
                  else
                    ..._frasesFavoritas.map((frase) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.star, color: Colors.amber, size: 20),
                        title: Text(
                          frase,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          onPressed: () {
                            setState(() {
                              _frasesFavoritas.remove(frase);
                            });
                            _guardarFavoritosPersistentes();
                          },
                        ),
                        onTap: () => _cargarFraseFavorita(frase),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.white,
            constraints: const BoxConstraints(minHeight: 55, maxHeight: 90),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _reproduciendoFrase
                      ? Scrollbar(
                    controller: _fraseScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _fraseScrollController,
                      scrollDirection: Axis.vertical,
                      child: _buildRichTextResaltadoAzul(),
                    ),
                  )
                      : KeyboardListener(
                    focusNode: _keyboardFocusNode,
                    onKeyEvent: (KeyEvent event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.backspace) {
                        _borrarPalabraCompleta();
                      }
                    },
                    child: Scrollbar(
                      controller: _fraseScrollController,
                      thumbVisibility: true,
                      child: TextField(
                        controller: _fraseController,
                        focusNode: _fraseFocusNode,
                        scrollController: _fraseScrollController,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                        decoration: const InputDecoration(
                          hintText: "Toca los pictogramas para construir la frase...",
                          hintStyle: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.normal,
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.only(right: 8),
                        ),
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _fraseController,
                  builder: (context, value, child) {
                    if (value.text.isNotEmpty) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _reproduciendoFrase ? Icons.volume_up : Icons.play_arrow,
                              color: _reproduciendoFrase ? Colors.blue : Colors.black,
                            ),
                            onPressed: _leerFraseCompleta,
                            tooltip: 'Leer frase completa',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.black),
                            onPressed: _limpiarFrase,
                            tooltip: 'Limpiar frase completa',
                          ),
                          IconButton(
                            icon: Icon(
                              esFavorita ? Icons.star : Icons.star_border,
                              color: esFavorita ? Colors.amber : Colors.black54,
                            ),
                            onPressed: _toggleFavorito,
                            tooltip: 'Agregar a Favoritos',
                          ),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: TextField(
              controller: _busquedaController,
              onChanged: (val) {
                setState(() {
                  _busquedaQuery = val.toLowerCase().trim();
                });
              },
              cursorColor: Colors.black,
              decoration: InputDecoration(
                hintText: 'Buscar pictograma o palabra...',
                fillColor: Colors.white,
                filled: true,
                prefixIcon: const Icon(Icons.search, color: Colors.black54),
                suffixIcon: _busquedaQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.black54),
                  onPressed: () {
                    _busquedaController.clear();
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _busquedaQuery = '';
                    });
                  },
                )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: const BorderSide(color: Color(0xFF5A97B8), width: 2),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                ),
              ),
            ),
          ),
          Expanded(
            child: _busquedaQuery.isNotEmpty
                ? _ResultadoBusquedaView(
              query: _busquedaQuery,
              onSeleccionar: _agregarAFrase,
              tiempoVerbal: _tiempoVerbalSeleccionado,
              onTiempoVerbalChanged: (nuevoTiempo) {
                setState(() {
                  _tiempoVerbalSeleccionado = nuevoTiempo;
                });
              },
            )
                : Navigator(
              key: _nestedNavigatorKey,
              onGenerateRoute: (settings) {
                return MaterialPageRoute(
                  builder: (context) => CategoriasScreen(
                    onSeleccionar: _agregarAFrase,
                    nestedNavigatorKey: _nestedNavigatorKey,
                    tiempoVerbal: _tiempoVerbalSeleccionado,
                    onTiempoVerbalChanged: (nuevoTiempo) {
                      setState(() {
                        _tiempoVerbalSeleccionado = nuevoTiempo;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRichTextResaltadoAzul() {
    final palabras = _fraseController.text.trim().split(RegExp(r'\s+'));

    return RichText(
      text: TextSpan(
        children: List.generate(palabras.length, (index) {
          final esPalabraActual = index == _indicePalabraLeyendo;
          return TextSpan(
            text: '${palabras[index]} ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: esPalabraActual ? Colors.blue.shade900 : Colors.black87,
              backgroundColor: esPalabraActual ? Colors.blue.shade100 : Colors.transparent,
              decoration: TextDecoration.none,
            ),
          );
        }),
      ),
    );
  }
}

// PANTALLA PARA ELIMINAR PICTOGRAMAS PERSONALIZADOS
class EliminarPictogramasScreen extends StatefulWidget {
  const EliminarPictogramasScreen({super.key});

  @override
  State<EliminarPictogramasScreen> createState() => _EliminarPictogramasScreenState();
}

class _EliminarPictogramasScreenState extends State<EliminarPictogramasScreen> {
  bool _huboCambios = false;

  void _confirmarEliminar(Pictograma p) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Pictograma'),
        content: Text('¿Deseas eliminar el pictograma "${p.etiqueta.toUpperCase()}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await PictogramaService.eliminarPictogramaPersonalizado(p.id);
              _huboCambios = true;
              if (mounted) {
                Navigator.of(context).pop();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pictograma eliminado correctamente')),
                );
              }
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final personalizaciones = PictogramaService.obtenerPictogramasPersonalizados();
    const colorAzul = Color(0xFF5A97B8);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _huboCambios) {
          // Permite refrescar la lista principal al volver hacia atrás
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ELIMINAR PICTOGRAMAS'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_huboCambios),
          ),
        ),
        body: personalizaciones.isEmpty
            ? const Center(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Text(
              'No hay pictogramas agregados por el usuario para eliminar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
        )
            : GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.8,
          ),
          itemCount: personalizaciones.length,
          itemBuilder: (context, index) {
            final item = personalizaciones[index];
            return Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: colorAzul, width: 2),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4, top: 4, right: 4, bottom: 2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(item.imagenUrl),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.image_not_supported,
                                size: 32,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                        child: Text(
                          item.etiqueta.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorAzul,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: InkWell(
                      onTap: () => _confirmarEliminar(item),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.delete,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class AgregarPictogramaScreen extends StatefulWidget {
  const AgregarPictogramaScreen({super.key});

  @override
  State<AgregarPictogramaScreen> createState() => _AgregarPictogramaScreenState();
}

class _AgregarPictogramaScreenState extends State<AgregarPictogramaScreen> {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _nuevaCategoriaController = TextEditingController();
  final TextEditingController _nuevaSubcategoriaController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  File? _imagenSeleccionada;
  String _categoriaSeleccionada = 'SUJETOS';
  String _subcategoriaSeleccionada = 'GENERAL';

  bool _creandoNuevaCategoria = false;
  bool _creandoNuevaSubcategoria = false;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    final categorias = PictogramaService.categoriasArchivos.keys.toList();
    if (categorias.isNotEmpty) {
      _categoriaSeleccionada = categorias.first.toUpperCase();
      final subs = _obtenerSubcategoriasDisponibles();
      if (subs.isNotEmpty) {
        _subcategoriaSeleccionada = subs.first.toUpperCase();
      }
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _nuevaCategoriaController.dispose();
    _nuevaSubcategoriaController.dispose();
    super.dispose();
  }

  List<String> _obtenerSubcategoriasDisponibles() {
    final catUpper = _categoriaSeleccionada.toUpperCase();
    final archivos = PictogramaService.categoriasArchivos[catUpper] ?? [];
    List<String> subs = [];

    for (String ruta in archivos) {
      String nombreSub = ruta
          .split('/')
          .last
          .replaceAll('.json', '')
          .replaceAll('_', ' ')
          .toUpperCase();
      if (!subs.contains(nombreSub)) {
        subs.add(nombreSub);
      }
    }

    if (subs.isEmpty) {
      subs.add('GENERAL');
    }

    return subs;
  }

  Future<void> _seleccionarImagen(ImageSource origen) async {
    final XFile? foto = await _picker.pickImage(source: origen, imageQuality: 85);
    if (foto != null) {
      setState(() {
        _imagenSeleccionada = File(foto.path);
      });
    }
  }

  Future<void> _guardarPictograma() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, escribe un nombre para el pictograma')),
      );
      return;
    }

    if (_imagenSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona una imagen o toma una foto')),
      );
      return;
    }

    // RESOLVER CATEGORÍA PRINCIPAL EN MAYÚSCULAS
    String categoriaFinal = _categoriaSeleccionada.toUpperCase();
    if (_creandoNuevaCategoria) {
      categoriaFinal = _nuevaCategoriaController.text.trim().toUpperCase();
      if (categoriaFinal.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escribe el nombre de la nueva categoría')),
        );
        return;
      }
      await PictogramaService.agregarCategoriaNueva(categoriaFinal);
    }

    // RESOLVER SUBCATEGORÍA EN MAYÚSCULAS
    String subcategoriaFinal = _subcategoriaSeleccionada.toUpperCase();
    if (_creandoNuevaCategoria) {
      subcategoriaFinal = 'GENERAL';
    } else if (_creandoNuevaSubcategoria) {
      subcategoriaFinal = _nuevaSubcategoriaController.text.trim().toUpperCase();
      if (subcategoriaFinal.isEmpty) {
        subcategoriaFinal = 'GENERAL';
      }
    }

    setState(() => _cargando = true);

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final String nombreArchivo = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File imagenGuardada = await _imagenSeleccionada!.copy('${appDir.path}/$nombreArchivo');

      final nuevoPictograma = Pictograma(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        etiqueta: nombre,
        imagenUrl: imagenGuardada.path,
        tipoPalabra: categoriaFinal,
        subcategoria: subcategoriaFinal,
      );

      await PictogramaService.agregarPictogramaPersonalizado(categoriaFinal, nuevoPictograma);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Pictograma guardado con éxito!')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      print("Error al guardar pictograma: $e");
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const colorAzul = Color(0xFF5A97B8);
    final categoriasExistentes = PictogramaService.categoriasArchivos.keys
        .map((c) => c.toUpperCase())
        .toList();

    final subcategoriasExistentes = _obtenerSubcategoriasDisponibles();

    return Scaffold(
      appBar: AppBar(
        title: const Text('NUEVO PICTOGRAMA'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colorAzul, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
                  ],
                ),
                child: _imagenSeleccionada != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(_imagenSeleccionada!, fit: BoxFit.cover),
                )
                    : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_search, size: 48, color: colorAzul),
                    SizedBox(height: 6),
                    Text(
                      'SIN IMAGEN',
                      style: TextStyle(color: colorAzul, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorAzul,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.camera_alt, color: Colors.white),
                    label: const Text('CÁMARA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () => _seleccionarImagen(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorAzul,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.photo_library, color: Colors.white),
                    label: const Text('GALERÍA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () => _seleccionarImagen(ImageSource.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: 'NOMBRE / PALABRA',
                hintText: 'Ej. MANZANA, ABUELA, JUGAR...',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              value: _creandoNuevaCategoria ? 'NUEVA' : _categoriaSeleccionada.toUpperCase(),
              decoration: const InputDecoration(
                labelText: 'CATEGORÍA PRINCIPAL',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              items: [
                ...categoriasExistentes.map((cat) {
                  return DropdownMenuItem(value: cat, child: Text(cat));
                }),
                const DropdownMenuItem(
                  value: 'NUEVA',
                  child: Text('➕ CREAR NUEVA CATEGORÍA...', style: TextStyle(color: colorAzul, fontWeight: FontWeight.bold)),
                ),
              ],
              onChanged: (val) {
                if (val == 'NUEVA') {
                  setState(() {
                    _creandoNuevaCategoria = true;
                    _creandoNuevaSubcategoria = false;
                  });
                } else if (val != null) {
                  setState(() {
                    _creandoNuevaCategoria = false;
                    _categoriaSeleccionada = val.toUpperCase();
                    final nuevasSubs = _obtenerSubcategoriasDisponibles();
                    _subcategoriaSeleccionada = nuevasSubs.first.toUpperCase();
                    _creandoNuevaSubcategoria = false;
                  });
                }
              },
            ),

            if (_creandoNuevaCategoria) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _nuevaCategoriaController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'NOMBRE DE LA NUEVA CATEGORÍA',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ],

            if (!_creandoNuevaCategoria) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _creandoNuevaSubcategoria ? 'NUEVA_SUB' : _subcategoriaSeleccionada.toUpperCase(),
                decoration: const InputDecoration(
                  labelText: 'SUBCATEGORÍA',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: [
                  ...subcategoriasExistentes.map((sub) {
                    return DropdownMenuItem(value: sub.toUpperCase(), child: Text(sub.toUpperCase()));
                  }),
                  const DropdownMenuItem(
                    value: 'NUEVA_SUB',
                    child: Text('➕ CREAR NUEVA SUBCATEGORÍA...', style: TextStyle(color: colorAzul, fontWeight: FontWeight.bold)),
                  ),
                ],
                onChanged: (val) {
                  if (val == 'NUEVA_SUB') {
                    setState(() => _creandoNuevaSubcategoria = true);
                  } else if (val != null) {
                    setState(() {
                      _creandoNuevaSubcategoria = false;
                      _subcategoriaSeleccionada = val.toUpperCase();
                    });
                  }
                },
              ),

              if (_creandoNuevaSubcategoria) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _nuevaSubcategoriaController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'NOMBRE DE LA NUEVA SUBCATEGORÍA',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ],
            ],

            const SizedBox(height: 28),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorAzul,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _cargando ? null : _guardarPictograma,
              child: _cargando
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                'GUARDAR PICTOGRAMA',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultadoBusquedaView extends StatefulWidget {
  final String query;
  final Function(Pictograma) onSeleccionar;
  final String tiempoVerbal;
  final ValueChanged<String> onTiempoVerbalChanged;

  const _ResultadoBusquedaView({
    required this.query,
    required this.onSeleccionar,
    required this.tiempoVerbal,
    required this.onTiempoVerbalChanged,
  });

  @override
  State<_ResultadoBusquedaView> createState() => _ResultadoBusquedaViewState();
}

class _ResultadoBusquedaViewState extends State<_ResultadoBusquedaView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Pictograma>>(
      future: PictogramaService.cargarTodos(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.black));
        }

        final todos = snapshot.data ?? [];
        final filtrados = todos.where((p) {
          final queryLimpia = widget.query.toLowerCase();
          final coincideEtiqueta = p.etiqueta.toLowerCase().contains(queryLimpia);
          final coincideSubcat = p.subcategoria.toLowerCase().contains(queryLimpia);

          bool coincideConjugacion = false;
          if (p.jsonRaw != null && p.jsonRaw!['conjugaciones'] is Map) {
            final mapConj = p.jsonRaw!['conjugaciones'] as Map;
            coincideConjugacion = mapConj.values.any((v) => v.toString().toLowerCase().contains(queryLimpia));
          }

          return coincideEtiqueta || coincideSubcat || coincideConjugacion;
        }).toList();

        if (filtrados.isEmpty) {
          return const Center(child: Text('No se encontraron palabras.'));
        }

        final contieneVerbos = filtrados.any((p) =>
        p.tipoPalabra.toLowerCase().contains('verbo') ||
            p.subcategoria.toUpperCase().contains('VERBO') ||
            p.jsonRaw?.containsKey('conjugaciones') == true);

        return Column(
          children: [
            if (contieneVerbos)
              SelectorTiempoVerbalBar(
                tiempoVerbal: widget.tiempoVerbal,
                onTiempoChanged: widget.onTiempoVerbalChanged,
              ),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(left: 8, top: 8, bottom: 8, right: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: filtrados.length,
                  itemBuilder: (context, index) {
                    final item = filtrados[index];
                    return PictogramaTarjeta(
                      item: item,
                      tiempoVerbal: widget.tiempoVerbal,
                      onTap: () => widget.onSeleccionar(item),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class SelectorTiempoVerbalBar extends StatelessWidget {
  final String tiempoVerbal;
  final ValueChanged<String> onTiempoChanged;

  const SelectorTiempoVerbalBar({
    super.key,
    required this.tiempoVerbal,
    required this.onTiempoChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white70,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 8),
          SegmentedButton<String>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(value: 'pasado', label: Text('PASADO', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 'presente', label: Text('PRESENTE', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 'futuro', label: Text('FUTURO', style: TextStyle(fontSize: 11))),
            ],
            selected: {tiempoVerbal},
            onSelectionChanged: (Set<String> newSelection) {
              onTiempoChanged(newSelection.first);
            },
          ),
        ],
      ),
    );
  }
}

class CategoriasScreen extends StatefulWidget {
  final Function(Pictograma) onSeleccionar;
  final GlobalKey<NavigatorState> nestedNavigatorKey;
  final String tiempoVerbal;
  final ValueChanged<String> onTiempoVerbalChanged;

  const CategoriasScreen({
    super.key,
    required this.onSeleccionar,
    required this.nestedNavigatorKey,
    required this.tiempoVerbal,
    required this.onTiempoVerbalChanged,
  });

  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, String> _portadasCategorias = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _obtenerImagenAleatoria(List<Pictograma> items) {
    final conImagen = items.where((p) => p.imagenUrl.trim().isNotEmpty).toList();
    if (conImagen.isEmpty) return '';
    final random = Random();
    return conImagen[random.nextInt(conImagen.length)].imagenUrl;
  }

  @override
  Widget build(BuildContext context) {
    final nombresCategorias = PictogramaService.categoriasArchivos.keys.toList();

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      trackVisibility: true,
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12, right: 18),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.85,
        ),
        itemCount: nombresCategorias.length,
        itemBuilder: (context, index) {
          final categoriaNombre = nombresCategorias[index].toUpperCase();
          final listaArchivos = PictogramaService.categoriasArchivos[nombresCategorias[index]] ?? [];

          return FutureBuilder<List<Pictograma>>(
            future: PictogramaService.cargarPorCategoriaPrincipal(categoriaNombre),
            builder: (context, snapshot) {
              final items = snapshot.data ?? [];

              if (!_portadasCategorias.containsKey(categoriaNombre) && items.isNotEmpty) {
                _portadasCategorias[categoriaNombre] = _obtenerImagenAleatoria(items);
              }

              return FolderCard(
                titulo: categoriaNombre,
                icono: Icons.folder,
                color: const Color(0xFF5A97B8),
                imagenUrl: _portadasCategorias[categoriaNombre],
                onTap: () async {
                  if (items.isEmpty) return;

                  if (listaArchivos.length > 1) {
                    await widget.nestedNavigatorKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (context) => SubcategoriasScreen(
                          categoriaNombre: categoriaNombre,
                          rutasArchivos: listaArchivos,
                          onSeleccionar: widget.onSeleccionar,
                          nestedNavigatorKey: widget.nestedNavigatorKey,
                          tiempoVerbal: widget.tiempoVerbal,
                          onTiempoVerbalChanged: widget.onTiempoVerbalChanged,
                        ),
                      ),
                    );
                  } else {
                    await widget.nestedNavigatorKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (context) => PictogramasScreen(
                          titulo: categoriaNombre,
                          pictogramas: items,
                          onSeleccionar: widget.onSeleccionar,
                          tiempoVerbal: widget.tiempoVerbal,
                          onTiempoVerbalChanged: widget.onTiempoVerbalChanged,
                          categoriaPadre: categoriaNombre,
                        ),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

class SubcategoriasScreen extends StatefulWidget {
  final String categoriaNombre;
  final List<String> rutasArchivos;
  final Function(Pictograma) onSeleccionar;
  final GlobalKey<NavigatorState> nestedNavigatorKey;
  final String tiempoVerbal;
  final ValueChanged<String> onTiempoVerbalChanged;

  const SubcategoriasScreen({
    super.key,
    required this.categoriaNombre,
    required this.rutasArchivos,
    required this.onSeleccionar,
    required this.nestedNavigatorKey,
    required this.tiempoVerbal,
    required this.onTiempoVerbalChanged,
  });

  @override
  State<SubcategoriasScreen> createState() => _SubcategoriasScreenState();
}

class _SubcategoriasScreenState extends State<SubcategoriasScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, String> _portadasSubcategorias = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _obtenerImagenAleatoria(List<Pictograma> items) {
    final conImagen = items.where((p) => p.imagenUrl.trim().isNotEmpty).toList();
    if (conImagen.isEmpty) return '';
    final random = Random();
    return conImagen[random.nextInt(conImagen.length)].imagenUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          color: Colors.white24,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Regresar',
              ),
              Expanded(
                child: Text(
                  widget.categoriaNombre.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            trackVisibility: true,
            child: GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12, right: 18),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemCount: widget.rutasArchivos.length,
              itemBuilder: (context, index) {
                final ruta = widget.rutasArchivos[index];
                final nombreBloque = ruta
                    .split('/')
                    .last
                    .replaceAll('.json', '')
                    .replaceAll('_', ' ')
                    .toUpperCase();

                return FutureBuilder<List<Pictograma>>(
                  future: PictogramaService.cargarPorArchivoJson(ruta),
                  builder: (context, snapshot) {
                    final items = snapshot.data ?? [];

                    if (!_portadasSubcategorias.containsKey(nombreBloque) && items.isNotEmpty) {
                      _portadasSubcategorias[nombreBloque] = _obtenerImagenAleatoria(items);
                    }

                    return FolderCard(
                      titulo: nombreBloque,
                      icono: Icons.folder_open,
                      color: const Color(0xFF5A97B8),
                      imagenUrl: _portadasSubcategorias[nombreBloque],
                      onTap: () async {
                        if (items.isEmpty) return;

                        final mapaDivisiones =
                        PictogramaService.obtenerSubdivisionesSiAplica(items, nombreBloque);

                        if (mapaDivisiones.isNotEmpty) {
                          await widget.nestedNavigatorKey.currentState?.push(
                            MaterialPageRoute(
                              builder: (context) => SubdivisionesScreen(
                                tituloPadre: nombreBloque,
                                agrupados: mapaDivisiones,
                                onSeleccionar: widget.onSeleccionar,
                                nestedNavigatorKey: widget.nestedNavigatorKey,
                                tiempoVerbal: widget.tiempoVerbal,
                                onTiempoVerbalChanged: widget.onTiempoVerbalChanged,
                                categoriaPadre: widget.categoriaNombre,
                              ),
                            ),
                          );
                        } else {
                          await widget.nestedNavigatorKey.currentState?.push(
                            MaterialPageRoute(
                              builder: (context) => PictogramasScreen(
                                titulo: nombreBloque,
                                pictogramas: items,
                                onSeleccionar: widget.onSeleccionar,
                                tiempoVerbal: widget.tiempoVerbal,
                                onTiempoVerbalChanged: widget.onTiempoVerbalChanged,
                                categoriaPadre: widget.categoriaNombre,
                              ),
                            ),
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class SubdivisionesScreen extends StatefulWidget {
  final String tituloPadre;
  final Map<String, List<Pictograma>> agrupados;
  final Function(Pictograma) onSeleccionar;
  final GlobalKey<NavigatorState> nestedNavigatorKey;
  final String tiempoVerbal;
  final ValueChanged<String> onTiempoVerbalChanged;
  final String categoriaPadre;

  const SubdivisionesScreen({
    super.key,
    required this.tituloPadre,
    required this.agrupados,
    required this.onSeleccionar,
    required this.nestedNavigatorKey,
    required this.tiempoVerbal,
    required this.onTiempoVerbalChanged,
    required this.categoriaPadre,
  });

  @override
  State<SubdivisionesScreen> createState() => _SubdivisionesScreenState();
}

class _SubdivisionesScreenState extends State<SubdivisionesScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, String> _portadasSubdivisiones = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _obtenerImagenAleatoria(List<Pictograma> items) {
    final conImagen = items.where((p) => p.imagenUrl.trim().isNotEmpty).toList();
    if (conImagen.isEmpty) return '';
    final random = Random();
    return conImagen[random.nextInt(conImagen.length)].imagenUrl;
  }

  @override
  Widget build(BuildContext context) {
    final llavesSub = widget.agrupados.keys.toList();

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          color: Colors.white24,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Regresar',
              ),
              Expanded(
                child: Text(
                  '${widget.categoriaPadre.toUpperCase()} > ${widget.tituloPadre.toUpperCase()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            trackVisibility: true,
            child: GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12, right: 18),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemCount: llavesSub.length,
              itemBuilder: (context, index) {
                final subNombre = llavesSub[index].toUpperCase();
                final items = widget.agrupados[llavesSub[index]] ?? [];

                if (!_portadasSubdivisiones.containsKey(subNombre) && items.isNotEmpty) {
                  _portadasSubdivisiones[subNombre] = _obtenerImagenAleatoria(items);
                }

                return FolderCard(
                  titulo: subNombre,
                  icono: Icons.folder,
                  color: const Color(0xFF5A97B8),
                  imagenUrl: _portadasSubdivisiones[subNombre],
                  onTap: () async {
                    await widget.nestedNavigatorKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (context) => PictogramasScreen(
                          titulo: subNombre,
                          pictogramas: items,
                          onSeleccionar: widget.onSeleccionar,
                          tiempoVerbal: widget.tiempoVerbal,
                          onTiempoVerbalChanged: widget.onTiempoVerbalChanged,
                          categoriaPadre: widget.categoriaPadre,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class PictogramasScreen extends StatefulWidget {
  final String titulo;
  final List<Pictograma> pictogramas;
  final Function(Pictograma) onSeleccionar;
  final String tiempoVerbal;
  final ValueChanged<String> onTiempoVerbalChanged;
  final String categoriaPadre;

  const PictogramasScreen({
    super.key,
    required this.titulo,
    required this.pictogramas,
    required this.onSeleccionar,
    required this.tiempoVerbal,
    required this.onTiempoVerbalChanged,
    required this.categoriaPadre,
  });

  @override
  State<PictogramasScreen> createState() => _PictogramasScreenState();
}

class _PictogramasScreenState extends State<PictogramasScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esSeccionVerbos = widget.categoriaPadre.toUpperCase().contains('VERBO') ||
        widget.titulo.toUpperCase().contains('VERBO') ||
        widget.pictogramas.any((p) =>
        p.tipoPalabra.toLowerCase().contains('verbo') ||
            p.subcategoria.toUpperCase().contains('VERBO') ||
            p.jsonRaw?.containsKey('conjugaciones') == true);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          color: Colors.white24,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Regresar',
              ),
              Expanded(
                child: Text(
                  widget.titulo.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (esSeccionVerbos)
          SelectorTiempoVerbalBar(
            tiempoVerbal: widget.tiempoVerbal,
            onTiempoChanged: widget.onTiempoVerbalChanged,
          ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            trackVisibility: true,
            child: GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(left: 8, top: 8, bottom: 8, right: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.85,
              ),
              itemCount: widget.pictogramas.length,
              itemBuilder: (context, index) {
                final item = widget.pictogramas[index];
                return PictogramaTarjeta(
                  item: item,
                  tiempoVerbal: widget.tiempoVerbal,
                  onTap: () => widget.onSeleccionar(item),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class FolderCard extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final Color color;
  final String? imagenUrl;
  final VoidCallback onTap;

  const FolderCard({
    super.key,
    required this.titulo,
    required this.icono,
    required this.color,
    this.imagenUrl,
    required this.onTap,
  });

  Widget _buildImageWidget(String path) {
    final rutaLimpia = path.trim();

    if (File(rutaLimpia).existsSync()) {
      return Image.file(
        File(rutaLimpia),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(icono, size: 40, color: const Color(0xFF5A97B8)),
      );
    }

    final esAssetLocal = rutaLimpia.startsWith('assets/') ||
        rutaLimpia.startsWith('assets-adicionales/');
    if (esAssetLocal) {
      return Image.asset(
        rutaLimpia,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(icono, size: 40, color: const Color(0xFF5A97B8)),
      );
    }

    return Image.network(
      rutaLimpia,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Icon(icono, size: 40, color: const Color(0xFF5A97B8)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tieneImagen = imagenUrl != null && imagenUrl!.trim().isNotEmpty;
    const colorBordeAzul = Color(0xFF5A97B8);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorBordeAzul, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 6.0, top: 6.0, right: 6.0, bottom: 2.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: tieneImagen
                          ? _buildImageWidget(imagenUrl!)
                          : Icon(icono, size: 40, color: colorBordeAzul),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
                child: Text(
                  titulo.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: colorBordeAzul,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PictogramaTarjeta extends StatelessWidget {
  final Pictograma item;
  final String? tiempoVerbal;
  final VoidCallback onTap;

  const PictogramaTarjeta({
    super.key,
    required this.item,
    this.tiempoVerbal,
    required this.onTap,
  });

  Widget _buildImageWidget(String path) {
    final rutaLimpia = path.trim();

    if (File(rutaLimpia).existsSync()) {
      return Image.file(
        File(rutaLimpia),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.image_not_supported,
          size: 36,
          color: Colors.grey,
        ),
      );
    }

    final esAssetLocal = rutaLimpia.startsWith('assets/') ||
        rutaLimpia.startsWith('assets-adicionales/');
    if (esAssetLocal) {
      return Image.asset(
        rutaLimpia,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.image_not_supported,
          size: 36,
          color: Colors.grey,
        ),
      );
    }

    return Image.network(
      rutaLimpia,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.image_not_supported,
        size: 36,
        color: Colors.grey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String textoMostrar = item.etiqueta;
    const colorBordeAzul = Color(0xFF5A97B8);

    final esVerbo = item.tipoPalabra.toLowerCase().contains('verbo') ||
        item.subcategoria.toUpperCase().contains('VERBO') ||
        item.jsonRaw?.containsKey('conjugaciones') == true;

    if (esVerbo && tiempoVerbal != null) {
      textoMostrar = PictogramaService.obtenerVerboConjugado(
        item,
        [],
        tiempo: tiempoVerbal!,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorBordeAzul, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 6.0, top: 6.0, right: 6.0, bottom: 2.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: item.imagenUrl.trim().isNotEmpty
                          ? _buildImageWidget(item.imagenUrl)
                          : const Icon(
                        Icons.image_not_supported,
                        size: 36,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
                child: Text(
                  textoMostrar.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: colorBordeAzul,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}