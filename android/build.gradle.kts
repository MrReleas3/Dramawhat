allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
        maven { url = uri("https://jcenter.bintray.com") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val androidExt = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            if (androidExt != null) {
                // AGP 8.0+ Namespace Fix
                if (androidExt.namespace == null) {
                    androidExt.namespace = "com.vad_app." + project.name.replace(":", ".")
                }
                
                // SDK Version Fix
                if (androidExt.compileSdkVersion != null) {
                    val current = androidExt.compileSdkVersion!!.substringAfterLast("-").toIntOrNull() ?: 0
                    if (current < 36) androidExt.compileSdkVersion(36)
                }

                // JVM Target Consistency Fix
                androidExt.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                androidExt.compileOptions.targetCompatibility = JavaVersion.VERSION_17
            }
            
            // AGP 8.0+ Manifest Package Fix
            val manifestFile = file("src/main/AndroidManifest.xml")
            if (manifestFile.exists()) {
                val content = manifestFile.readText()
                if (content.contains("package=")) {
                    val newContent = content.replace(Regex("package=\"[^\"]*\""), "")
                    manifestFile.writeText(newContent)
                }
            }
        }
    }

    // JVM Consistency across subprojects
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
    
    tasks.matching { it.name.startsWith("compile") && it.name.endsWith("Kotlin") }.configureEach {
        try {
            // Use reflection to avoid script compile errors for Kotlin types
            if (hasProperty("kotlinOptions")) {
                val ko = property("kotlinOptions")
                ko?.javaClass?.getMethod("setJvmTarget", String::class.java)?.invoke(ko, "17")
            }
        } catch (e: Exception) {}
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
