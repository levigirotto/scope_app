import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(const ScopeApp());
}

// Paleta do projeto (variante clara)
class ScopeColors {
  static const background = Color(0xFFF4F7FA);
  static const panel = Color(0xFFFFFFFF);
  static const border = Color(0xFFDCE4ED);
  static const teal = Color(0xFF109C86);
  static const amber = Color(0xFFE8933F);
  static const textPrimary = Color(0xFF1A2B3C);
  static const textDim = Color(0xFF6E86A3);
  static const danger = Color(0xFFE5473B);
}

class ScopeApp extends StatelessWidget {
  const ScopeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scope',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: ScopeColors.background,
        colorScheme: ColorScheme.light(
          primary: ScopeColors.teal,
          secondary: ScopeColors.amber,
          surface: ScopeColors.panel,
        ),
        fontFamily: 'monospace',
      ),
      home: const KeepTrackScreen(),
    );
  }
}

class KeepTrackScreen extends StatefulWidget {
  const KeepTrackScreen({super.key});

  @override
  State<KeepTrackScreen> createState() => _KeepTrackScreenState();
}

class _KeepTrackScreenState extends State<KeepTrackScreen> {
  static const String broker = 'broker.hivemq.com';
  static const int port = 1883;
  static const String topicoDados = 'keeptrack/dados';
  static const String topicoRele = 'keeptrack/rele';

  late MqttServerClient client;

  bool conectado = false;
  bool releLigado = true; // ESP32 inicia com o relé ligado
  double? potencia;
  double? consumo;
  DateTime? ultimaLeitura;

  @override
  void initState() {
    super.initState();
    _conectar();
  }

  Future<void> _conectar() async {
    client = MqttServerClient.withPort(
      broker,
      'scope-app-${DateTime.now().millisecondsSinceEpoch}',
      port,
    );
    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.onDisconnected = () => setState(() => conectado = false);
    client.onConnected = () => setState(() => conectado = true);

    try {
      await client.connect();
    } catch (e) {
      client.disconnect();
      return;
    }

    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      setState(() => conectado = true);
      client.subscribe(topicoDados, MqttQos.atMostOnce);

      client.updates!.listen((events) {
        final recMess = events[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );
        _processarMensagem(payload);
      });
    }
  }

  void _processarMensagem(String payload) {
    try {
      final data = jsonDecode(payload);
      setState(() {
        if (data['potencia'] != null) {
          potencia = (data['potencia'] as num).toDouble();
        }
        if (data['consumo'] != null) {
          consumo = (data['consumo'] as num).toDouble();
        }
        ultimaLeitura = DateTime.now();
      });
    } catch (_) {
      // payload inválido, ignora
    }
  }

  void _alternarRele() {
    final novoEstado = !releLigado;
    final builder = MqttClientPayloadBuilder();
    builder.addString(novoEstado ? 'ON' : 'OFF');

    client.publishMessage(topicoRele, MqttQos.atMostOnce, builder.payload!);

    setState(() => releLigado = novoEstado);
  }

  @override
  void dispose() {
    client.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 28),
              _buildReleButton(),
              const SizedBox(height: 14),
              _buildMetricCard(
                label: 'POTÊNCIA UTILIZADA',
                value: potencia?.toStringAsFixed(0) ?? '—',
                unit: 'W',
                destacado: (potencia ?? 0) > 5,
              ),
              const SizedBox(height: 14),
              _buildMetricCard(
                label: 'CONSUMO (kWh)',
                value: consumo?.toStringAsFixed(3) ?? '—',
                unit: 'kWh',
                destacado: (consumo ?? 0) > 0.005,
              ),
              const Spacer(),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: ScopeColors.textPrimary,
              letterSpacing: 0.5,
            ),
            children: [
              TextSpan(text: 'KEEP'),
              TextSpan(
                text: 'TRACK',
                style: TextStyle(color: ScopeColors.amber),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: conectado ? ScopeColors.teal : ScopeColors.danger,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              conectado ? 'conectado' : 'conectando…',
              style: const TextStyle(fontSize: 12, color: ScopeColors.textDim),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required String unit,
    required bool destacado,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: ScopeColors.panel,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ScopeColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1A2B3C),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 3,
            color: destacado ? ScopeColors.amber : ScopeColors.border,
            margin: const EdgeInsets.only(bottom: 12),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: ScopeColors.textDim,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                fontSize: 34,
                color: ScopeColors.textPrimary,
              ),
              children: [
                TextSpan(text: value),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: ScopeColors.amber,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: conectado ? _alternarRele : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: releLigado ? ScopeColors.teal : ScopeColors.panel,
          foregroundColor: releLigado ? Colors.white : ScopeColors.textPrimary,
          side: BorderSide(
            color: releLigado ? ScopeColors.teal : ScopeColors.border,
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          elevation: 0,
        ),
        child: Text(
          releLigado
              ? 'LIGADO — TOCAR PARA DESLIGAR'
              : 'DESLIGADO — TOCAR PARA LIGAR',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final texto = ultimaLeitura == null
        ? 'última leitura: —'
        : 'última leitura: ${ultimaLeitura!.hour.toString().padLeft(2, '0')}:${ultimaLeitura!.minute.toString().padLeft(2, '0')}:${ultimaLeitura!.second.toString().padLeft(2, '0')}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'broker.hivemq.com',
          style: TextStyle(fontSize: 11, color: ScopeColors.textDim),
        ),
        Text(
          texto,
          style: const TextStyle(fontSize: 11, color: ScopeColors.textDim),
        ),
      ],
    );
  }
}
