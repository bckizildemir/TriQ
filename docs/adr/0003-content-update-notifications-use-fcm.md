# Content update notifications use FCM as the APNs provider bridge

Content update notifications are delivered to iOS users through Apple Push Notification service, with Firebase Cloud Messaging acting as the provider bridge from Cloud Functions. We chose this over a direct APNs provider server because TTB already uses Firebase Auth, Firestore, Functions, and the Firebase Admin SDK; FCM gives the backend multicast delivery, token lifecycle integration, and one operational surface while still relying on Apple's notification delivery on device.

Direct APNs remains a viable future replacement only if Firebase stops being the backend control plane or if notification requirements outgrow FCM's iOS support.
