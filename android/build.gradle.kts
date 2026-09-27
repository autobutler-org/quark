import org.gradle.api.tasks.compile.JavaCompile

allprojects {
    repositories {
        google()
        mavenCentral()
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
    project.evaluationDependsOn(":app")
}

subprojects {
    // Some third-party Android plugins still default to Java 8 and trigger
    // obsolete-source warnings with newer JDKs. Normalize all Java compiles.
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// bonsoir_android 5.1.6 hardcodes compileSdk 33, which AGP 8.13+ rejects in its AAR
// metadata check (the libraries it pulls in need 34+). Remove this once bonsoir
// is on 7+, which currently cannot happen: flutter_probe_agent pins bonsoir ^5.
subprojects {
    if (name == "bonsoir_android") {
        afterEvaluate {
            extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
                compileSdk = 36
            }
        }
    }
}
