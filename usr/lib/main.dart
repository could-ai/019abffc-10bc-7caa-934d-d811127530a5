import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const SwingJumpApp());
}

class SwingJumpApp extends StatelessWidget {
  const SwingJumpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swing Jump',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  
  // Game State
  bool isPlaying = false;
  bool isGameOver = false;
  double score = 0;
  int diamonds = 0;
  
  // Physics
  Offset playerPos = const Offset(100, 300);
  Offset playerVel = const Offset(5, 0); // Initial forward velocity
  final double gravity = 0.25;
  final double jumpForce = 10.0;
  final double swingSpeed = 0.05;
  
  // Camera
  double cameraX = 0;
  
  // World
  List<Offset> bars = [];
  List<Offset> obstacles = [];
  List<Offset> diamondPositions = [];
  Offset? attachedBar;
  double ropeLength = 0;
  
  // Constants
  final double barRadius = 10.0;
  final double playerRadius = 15.0;
  final double obstacleSize = 30.0;
  final double diamondSize = 20.0;
  
  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_gameLoop);
    _resetGame();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _resetGame() {
    setState(() {
      isPlaying = false;
      isGameOver = false;
      score = 0;
      diamonds = 0;
      playerPos = const Offset(100, 300);
      playerVel = const Offset(6, -5); // Start with a little jump
      cameraX = 0;
      attachedBar = null;
      
      // Generate initial world
      bars.clear();
      obstacles.clear();
      diamondPositions.clear();
      _generateChunk(0);
    });
  }

  void _startGame() {
    if (!isPlaying && !isGameOver) {
      setState(() {
        isPlaying = true;
      });
      _ticker.start();
    } else if (isGameOver) {
      _resetGame();
      setState(() {
        isPlaying = true;
      });
      _ticker.start();
    }
  }

  void _generateChunk(double startX) {
    double currentX = startX;
    if (bars.isNotEmpty) {
      currentX = bars.last.dx;
    } else {
      // First bar
      bars.add(const Offset(300, 200));
      currentX = 300;
    }

    // Generate next 10 bars
    for (int i = 0; i < 10; i++) {
      double distance = 200 + Random().nextInt(150).toDouble();
      double heightChange = Random().nextInt(200).toDouble() - 100; // -100 to 100
      double newY = (bars.last.dy + heightChange).clamp(100.0, 500.0);
      
      currentX += distance;
      Offset newBar = Offset(currentX, newY);
      bars.add(newBar);

      // Chance to add diamond between bars
      if (Random().nextBool()) {
        diamondPositions.add(Offset(currentX - distance / 2, newY - 50));
      }

      // Chance to add obstacle (red block)
      if (Random().nextDouble() < 0.3) {
        obstacles.add(Offset(currentX - distance / 2, newY + 100));
      }
    }
  }

  void _gameLoop(Duration elapsed) {
    if (!isPlaying || isGameOver) return;

    setState(() {
      // 1. Update Physics
      if (attachedBar != null) {
        // SWINGING PHYSICS
        Offset toPlayer = playerPos - attachedBar!;
        double currentAngle = atan2(toPlayer.dy, toPlayer.dx);
        
        // Conservation of energy / pendulum approximation
        // Gravity accelerates the swing downwards
        double angularAcc = (-gravity / ropeLength) * cos(currentAngle);
        
        // Convert current velocity to angular velocity roughly
        // This is a simplified arcade physics model for "feel" rather than strict realism
        double angularVel = (playerVel.dx * cos(currentAngle) + playerVel.dy * sin(currentAngle)) / ropeLength;
        
        // Add gravity effect
        playerVel += Offset(0, gravity);
        
        // Constrain to rope length
        Offset direction = (playerPos - attachedBar!).directionVector;
        playerPos = attachedBar! + direction * ropeLength;
        
        // Damping/Air resistance slightly
        playerVel *= 0.995;
        
        // Important: In a rigid pendulum, velocity is tangent. 
        // We project velocity to be tangent to the circle
        Offset tangent = Offset(-direction.dy, direction.dx);
        double speed = playerVel.dx * tangent.dx + playerVel.dy * tangent.dy;
        playerVel = tangent * speed;

      } else {
        // FREE FALL PHYSICS
        playerVel += Offset(0, gravity);
        playerPos += playerVel;
      }

      // 2. Camera Follow
      // Keep player at roughly 1/3rd of the screen width
      double targetCameraX = playerPos.dx - MediaQuery.of(context).size.width * 0.3;
      if (targetCameraX > cameraX) {
        cameraX = targetCameraX;
      }

      // 3. World Generation & Cleanup
      if (bars.last.dx - cameraX < MediaQuery.of(context).size.width * 2) {
        _generateChunk(bars.last.dx);
      }
      // Remove objects far behind
      bars.removeWhere((b) => b.dx < cameraX - 200);
      obstacles.removeWhere((o) => o.dx < cameraX - 200);
      diamondPositions.removeWhere((d) => d.dx < cameraX - 200);

      // 4. Collision Detection
      
      // Diamonds
      diamondPositions.removeWhere((d) {
        if ((playerPos - d).distance < playerRadius + diamondSize) {
          diamonds++;
          return true;
        }
        return false;
      });

      // Obstacles (Game Over)
      for (var obs in obstacles) {
        Rect obsRect = Rect.fromCenter(center: obs, width: obstacleSize, height: obstacleSize);
        if (obsRect.overlaps(Rect.fromCircle(center: playerPos, radius: playerRadius))) {
          _gameOver();
          return;
        }
      }

      // Fall off screen (Game Over)
      if (playerPos.dy > MediaQuery.of(context).size.height + 100) {
        _gameOver();
      }

      // Update Score
      if (playerPos.dx > score) {
        score = playerPos.dx;
      }
    });
  }

  void _gameOver() {
    setState(() {
      isGameOver = true;
      isPlaying = false;
      attachedBar = null;
    });
    _ticker.stop();
  }

  void _handleTapDown(TapDownDetails details) {
    if (!isPlaying) {
      _startGame();
      return;
    }

    // Find nearest bar
    Offset? nearest;
    double minDist = double.infinity;
    
    // Search bars currently on screen or close to it
    for (var bar in bars) {
      double dist = (playerPos - bar).distance;
      if (dist < 300 && dist < minDist && bar.dx > playerPos.dx - 50) { // Can only grab bars reasonably close and mostly in front
        minDist = dist;
        nearest = bar;
      }
    }

    if (nearest != null) {
      setState(() {
        attachedBar = nearest;
        ropeLength = minDist;
        // Add a little boost when grabbing to keep momentum
        // playerVel += Offset(2, 0); 
      });
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (attachedBar != null) {
      setState(() {
        // Release boost
        // Calculate release velocity vector based on swing direction
        attachedBar = null;
        // Add a small "jump" impulse on release to make it feel responsive
        playerVel += Offset(2, -4); 
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: () {
          if (attachedBar != null) {
            setState(() {
              attachedBar = null;
            });
          }
        },
        child: Stack(
          children: [
            // Game World
            CustomPaint(
              painter: GamePainter(
                playerPos: playerPos,
                bars: bars,
                obstacles: obstacles,
                diamonds: diamondPositions,
                cameraX: cameraX,
                attachedBar: attachedBar,
                ropeLength: ropeLength,
              ),
              child: Container(),
            ),
            
            // UI Overlay
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Score: ${(score / 100).floor()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.diamond, color: Colors.cyanAccent),
                            const SizedBox(width: 4),
                            Text(
                              '$diamonds',
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Start / Game Over Screen
            if (!isPlaying)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.cyanAccent, width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isGameOver ? 'GAME OVER' : 'SWING JUMP',
                        style: TextStyle(
                          color: isGameOver ? Colors.redAccent : Colors.cyanAccent,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (isGameOver)
                        Text(
                          'Final Score: ${(score / 100).floor()}',
                          style: const TextStyle(color: Colors.white, fontSize: 20),
                        ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _startGame,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        ),
                        child: Text(
                          isGameOver ? 'TRY AGAIN' : 'TAP TO START',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Tap & Hold to Swing\nRelease to Fly',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GamePainter extends CustomPainter {
  final Offset playerPos;
  final List<Offset> bars;
  final List<Offset> obstacles;
  final List<Offset> diamonds;
  final double cameraX;
  final Offset? attachedBar;
  final double ropeLength;

  GamePainter({
    required this.playerPos,
    required this.bars,
    required this.obstacles,
    required this.diamonds,
    required this.cameraX,
    required this.attachedBar,
    required this.ropeLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [const Color(0xFF1A1A2E), const Color(0xFF16213E)],
      );
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Grid lines for speed effect
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    double gridSpacing = 100;
    double gridOffsetX = -(cameraX % gridSpacing);
    for (double i = gridOffsetX; i < size.width; i += gridSpacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }

    // Translate canvas for camera
    canvas.save();
    canvas.translate(-cameraX, 0);

    // Draw Rope
    if (attachedBar != null) {
      final ropePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(attachedBar!, playerPos, ropePaint);
    }

    // Draw Bars (Pivots)
    final barPaint = Paint()..color = Colors.grey;
    final barCenterPaint = Paint()..color = Colors.white;
    for (var bar in bars) {
      // Only draw if visible
      if (bar.dx > cameraX - 50 && bar.dx < cameraX + size.width + 50) {
        canvas.drawCircle(bar, 8, barPaint);
        canvas.drawCircle(bar, 3, barCenterPaint);
      }
    }

    // Draw Obstacles
    final obsPaint = Paint()..color = Colors.redAccent;
    for (var obs in obstacles) {
       if (obs.dx > cameraX - 50 && obs.dx < cameraX + size.width + 50) {
         canvas.drawRect(
           Rect.fromCenter(center: obs, width: 30, height: 30), 
           obsPaint
         );
       }
    }

    // Draw Diamonds
    final diamondPaint = Paint()..color = Colors.cyanAccent;
    for (var d in diamonds) {
      if (d.dx > cameraX - 50 && d.dx < cameraX + size.width + 50) {
        Path path = Path();
        path.moveTo(d.dx, d.dy - 10);
        path.lineTo(d.dx + 10, d.dy);
        path.lineTo(d.dx, d.dy + 10);
        path.lineTo(d.dx - 10, d.dy);
        path.close();
        canvas.drawPath(path, diamondPaint);
      }
    }

    // Draw Player
    final playerPaint = Paint()..color = Colors.orangeAccent;
    canvas.drawCircle(playerPos, 15, playerPaint);
    
    // Player Trail (Simple)
    final trailPaint = Paint()
      ..color = Colors.orangeAccent.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(playerPos - Offset(5, 0), 12, trailPaint);
    canvas.drawCircle(playerPos - Offset(10, 0), 8, trailPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) {
    return true; // Always repaint for game loop
  }
}

extension OffsetExtension on Offset {
  Offset get directionVector {
    double len = distance;
    if (len == 0) return Offset.zero;
    return this / len;
  }
}
