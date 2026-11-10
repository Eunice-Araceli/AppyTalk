class Pictograma {
  final String id;
  final String etiqueta;
  final String imagenUrl;
  final String tipoPalabra;
  final String subcategoria;
  final Map<String, dynamic>? jsonRaw;

  Pictograma({
    required this.id,
    required this.etiqueta,
    required this.imagenUrl,
    required this.tipoPalabra,
    required this.subcategoria,
    this.jsonRaw,
  });

  factory Pictograma.fromJson(Map<String, dynamic> json, {required String subcategoriaDefecto}) {
    String sub = json['subcategoria']?.toString() ??
        json['subCategoria']?.toString() ??
        json['categoria']?.toString() ??
        subcategoriaDefecto;

    String urlDetectada = json['imagen_url']?.toString() ??
        json['imagenUrl']?.toString() ??
        json['imagen']?.toString() ??
        json['url']?.toString() ??
        json['foto']?.toString() ??
        json['link']?.toString() ??
        '';

    return Pictograma(
      id: json['id']?.toString() ?? '',
      etiqueta: json['etiqueta']?.toString() ?? json['nombre']?.toString() ?? '',
      imagenUrl: urlDetectada.trim(),
      tipoPalabra: json['tipoPalabra']?.toString() ?? json['tipo']?.toString() ?? '',
      subcategoria: sub,
      jsonRaw: json,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'etiqueta': etiqueta,
      'imagen_url': imagenUrl,
      'tipoPalabra': tipoPalabra,
      'subcategoria': subcategoria,
      if (jsonRaw != null) ...jsonRaw!,
    };
  }
}