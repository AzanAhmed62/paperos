# PaperOS release shrinking rules.
#
# Flutter's own rules ship with the Gradle plugin. The entries below protect
# the two things that ProGuard cannot see are used: the platform channel
# handler classes (referenced only by name from Dart) and nothing else.

# The platform channel classes are instantiated reflectively by
# MainActivity.configureFlutterEngine only in the sense that Dart looks them up
# by channel name. Keeping the classes themselves is enough; their methods are
# resolved through @Keep-protected MethodCall dispatch.
-keep class dev.paperos.app.** { *; }

# Kotlin metadata used by the Flutter plugin registrant.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
