import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream
import java.net.URI
import groovy.json.JsonSlurper
import groovy.json.JsonOutput
import org.gradle.api.artifacts.transform.TransformAction
import org.gradle.api.artifacts.transform.TransformOutputs
import org.gradle.api.artifacts.transform.TransformParameters
import org.gradle.api.artifacts.transform.InputArtifact
import org.gradle.api.artifacts.type.ArtifactTypeDefinition
import org.gradle.api.attributes.Attribute
import org.gradle.api.file.FileSystemLocation
import org.gradle.api.provider.Provider
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.objectweb.asm.ClassWriter
import org.objectweb.asm.Opcodes

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Include only public client configuration, even for a plain `flutter build apk`.
val prepareCommunityCloudConfig = tasks.register("prepareCommunityCloudConfig") {
    val sourceConfig = rootProject.file("../config/supabase.local.json")
    val publicConfig = rootProject.file("../assets/config/supabase.public.json")
    inputs.file(sourceConfig).optional()
    outputs.file(publicConfig)
    doLast {
        if (!sourceConfig.exists()) return@doLast
        val config = try {
            JsonSlurper().parse(sourceConfig) as Map<*, *>
        } catch (_: Exception) {
            throw GradleException("Cloud configuration is invalid; check config/supabase.local.json")
        }
        val url = (config["SUPABASE_URL"] as? String)?.trim().orEmpty()
        val key = (config["SUPABASE_PUBLISHABLE_KEY"] as? String)?.trim().orEmpty()
        val uri = try { URI(url) } catch (_: Exception) { null }
        if (uri == null || uri.scheme != "https" || uri.host.isNullOrEmpty() ||
            uri.userInfo != null || uri.query != null || uri.fragment != null ||
            (uri.path.isNotEmpty() && uri.path != "/") || !key.startsWith("sb_publishable_")) {
            throw GradleException("Cloud configuration must contain an HTTPS API root and a publishable key")
        }
        publicConfig.parentFile.mkdirs()
        publicConfig.writeText(JsonOutput.toJson(mapOf(
            "SUPABASE_URL" to url.trimEnd('/'),
            "SUPABASE_PUBLISHABLE_KEY" to key
        )), Charsets.UTF_8)
    }
}

tasks.configureEach {
    if (name.startsWith("compileFlutterBuild")) dependsOn(prepareCommunityCloudConfig)
}

// POI's desktop mmap cleaner contains invokeExact (API 26). Imports below use
// InputStream-backed POIFS only, so disable mmap unmapping without changing minSdk
// or the parsers. Preserve the rest of the official artifact and its dependencies.
abstract class OfficePoiAndroidTransform : TransformAction<TransformParameters.None> {
    @get:InputArtifact
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val inputArtifact: Provider<FileSystemLocation>

    override fun transform(outputs: TransformOutputs) {
        val input = inputArtifact.get().asFile
        if (input.name != "poi-5.5.1.jar") {
            outputs.file(input)
            return
        }
        val writer = ClassWriter(0)
        val owner = "org/apache/poi/poifs/nio/CleanerUtil"
        writer.visit(Opcodes.V1_8, Opcodes.ACC_PUBLIC or Opcodes.ACC_FINAL, owner, null, "java/lang/Object", null)
        writer.visitField(Opcodes.ACC_PUBLIC or Opcodes.ACC_STATIC or Opcodes.ACC_FINAL,
            "UNMAP_SUPPORTED", "Z", null, 0).visitEnd()
        writer.visitField(Opcodes.ACC_PUBLIC or Opcodes.ACC_STATIC or Opcodes.ACC_FINAL,
            "UNMAP_NOT_SUPPORTED_REASON", "Ljava/lang/String;", null,
            "Android Office import uses in-memory POIFS; mmap unmapping is disabled").visitEnd()
        writer.visitMethod(Opcodes.ACC_PUBLIC or Opcodes.ACC_STATIC, "getCleaner",
            "()L${owner}\$BufferCleaner;", null, null).apply {
            visitCode()
            visitInsn(Opcodes.ACONST_NULL)
            visitInsn(Opcodes.ARETURN)
            visitMaxs(1, 0)
            visitEnd()
        }
        writer.visitEnd()
        ZipFile(input).use { zip ->
            ZipOutputStream(outputs.file("poi-5.5.1-android.jar").outputStream()).use { output ->
                for (entry in zip.entries()) {
                    output.putNextEntry(ZipEntry(entry.name))
                    if (entry.name == "$owner.class") {
                        output.write(writer.toByteArray())
                    } else {
                        zip.getInputStream(entry).use { it.copyTo(output) }
                    }
                    output.closeEntry()
                }
            }
        }
    }
}

val officeAndroidCompatible = Attribute.of("pxt.officeAndroidCompatible", Boolean::class.javaObjectType)
dependencies {
    artifactTypes.getByName("jar").attributes.attribute(officeAndroidCompatible, false)
    registerTransform(OfficePoiAndroidTransform::class) {
        from.attribute(ArtifactTypeDefinition.ARTIFACT_TYPE_ATTRIBUTE, "jar")
            .attribute(officeAndroidCompatible, false)
        to.attribute(ArtifactTypeDefinition.ARTIFACT_TYPE_ATTRIBUTE, "jar")
            .attribute(officeAndroidCompatible, true)
    }
}
configurations.configureEach {
    if (name.endsWith("CompileClasspath") || name.endsWith("RuntimeClasspath")) {
        attributes.attribute(officeAndroidCompatible, true)
    }
}

android {
    namespace = "com.example.pxt1"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    packaging {
        resources.merges += "META-INF/DEPENDENCIES"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.pxt1"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // Binary Word/PowerPoint text only; OOXML uses Android's ZIP/XML APIs.
    implementation("org.apache.poi:poi-scratchpad:5.5.1")
    // Bundle the non-Latin recognizers that LocalOcrClient can request.
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
}

flutter {
    source = "../.."
}
