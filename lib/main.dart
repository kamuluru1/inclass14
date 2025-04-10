import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'dart:async';

/// Top-level background message handler.
/// This function must be a top-level function (or static) so that it can be invoked by the messaging service.
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized in the background.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('Background message received: ${message.notification?.body}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register background message handler.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(MessagingTutorial());
}

/// The root widget of the application.
class MessagingTutorial extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Messaging & Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[200],
      ),
      home: ChatPage(title: 'Chat Room'),
    );
  }
}

/// ChatPage is a stateful widget that combines chat functionality
/// with Firebase Messaging to handle push notifications.
class ChatPage extends StatefulWidget {
  final String title;
  ChatPage({Key? key, required this.title}) : super(key: key);

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late FirebaseMessaging messaging;
  late StreamSubscription<RemoteMessage> _onMessageSubscription;
  late StreamSubscription<RemoteMessage> _onMessageOpenedSubscription;

  // Controller for the text input.
  final TextEditingController _messageController = TextEditingController();

  // Reference to the Firestore collection to store messages.
  final CollectionReference messagesCollection =
  FirebaseFirestore.instance.collection('messages');

  @override
  void initState() {
    super.initState();

    messaging = FirebaseMessaging.instance;

    // Request permissions for iOS.
    messaging.requestPermission(
      alert: true,
      sound: true,
      badge: true,
    ).then((settings) {
      print('User granted permission: ${settings.authorizationStatus}');
    }).catchError((error) {
      print('Error requesting permission: $error');
    });

    // Subscribe to a topic so you can receive broadcast notifications.
    messaging.subscribeToTopic("messaging").then((_) {
      print("Subscribed to topic 'messaging'");
    }).catchError((error) {
      print("Error subscribing to topic: $error");
    });

    // Retrieve the device token.
    messaging.getToken().then((token) {
      if (token != null) {
        print("Device Token: $token");
      }
    }).catchError((error) {
      print("Error retrieving token: $error");
    });

    // Listen for messages received when the app is in the foreground.
    _onMessageSubscription =
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          if (message.notification != null) {
            print("Foreground message: ${message.notification?.body}");
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(message.notification?.title ?? 'Notification'),
                content: Text(message.notification?.body ?? ''),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text("OK"),
                  )
                ],
              ),
            );
          }
        });

    // Listen for messages when the notification is clicked/opened.
    _onMessageOpenedSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          print("Notification clicked: ${message.notification?.body}");
          // Navigation or additional handling can be added here.
        });
  }

  @override
  void dispose() {
    _onMessageSubscription.cancel();
    _onMessageOpenedSubscription.cancel();
    _messageController.dispose();
    super.dispose();
  }

  /// Sends a message to the Firestore collection.
  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    await messagesCollection.add({
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _messageController.clear();
  }

  /// Builds the list of chat messages from Firestore.
  Widget _buildMessagesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: messagesCollection.orderBy('timestamp', descending: false).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading messages.'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        final messages = snapshot.data?.docs ?? [];
        return ListView.builder(
          padding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final data = messages[index].data() as Map<String, dynamic>;
            final text = data['text'] ?? '';
            Timestamp? timestamp = data['timestamp'] as Timestamp?;
            DateTime? time = timestamp != null
                ? DateTime.fromMillisecondsSinceEpoch(timestamp.millisecondsSinceEpoch)
                : null;
            return ChatBubble(
              message: text,
              timestamp: time,
            );
          },
        );
      },
    );
  }

  /// Builds the messaging UI including the chat messages list and input field.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        elevation: 2.0,
      ),
      body: Column(
        children: [
          // Expanded widget for messages list.
          Expanded(child: _buildMessagesList()),
          Divider(height: 1.0),
          // Input area.
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            color: Colors.white,
            child: SafeArea(
              child: Row(
                children: [
                  // Text field to input message.
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        border: InputBorder.none,
                      ),
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  // Send button.
                  IconButton(
                    icon: Icon(Icons.send, color: Colors.indigo),
                    onPressed: () {
                      _sendMessage(_messageController.text);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A custom widget to display individual chat messages in a bubble style.
class ChatBubble extends StatelessWidget {
  final String message;
  final DateTime? timestamp;

  const ChatBubble({Key? key, required this.message, this.timestamp})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Format the timestamp into a readable string if available.
    String timeString = timestamp != null
        ? "${timestamp!.hour.toString().padLeft(2, '0')}:${timestamp!.minute.toString().padLeft(2, '0')}"
        : '';

    return Container(
      margin: EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // You can add an avatar here if needed.
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.indigo,
            child: Text(
              message.isNotEmpty ? message[0].toUpperCase() : '',
              style: TextStyle(color: Colors.white),
            ),
          ),
          SizedBox(width: 8.0),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
              decoration: BoxDecoration(
                color: Colors.indigo[50],
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                  if (timeString.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        timeString,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
