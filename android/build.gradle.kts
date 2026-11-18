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

// The onnxruntime pub package pins compileSdkVersion 33 in its own Android
// module and comments that bumping it is a breaking change for older
// clients. AGP 9.1.1 (the minimum Flutter 3.44.2 enforces) checks AAR
// metadata strictly, and androidx.fragment 1.7.1 requires compileSdk >= 34,
// so the module is raised to the app's compileSdk (36, Flutter 3.44.2's own
// value) without touching the package. `plugins.withId` runs at plugin
// application (or immediately, if the plugin is already applied): the plain
// `afterEvaluate` variant failed with 'Cannot run Project.afterEvaluate
// when the project is already evaluated' because evaluationDependsOn(":app")
// forces evaluation before the root's subprojects block registers.
// AGP 9 renamed its implementation interfaces, so both the public DSL
// interface and the legacy one are tried; a miss fails loudly with the
// actual class name instead of silently leaving android-33 in place.
subprojects {
    if (name == "onnxruntime") {
        plugins.withId("com.android.library") {
            val androidExt = extensions.findByName("android")
            when (androidExt) {
                is com.android.build.api.dsl.LibraryExtension ->
                    androidExt.compileSdk = 36
                is com.android.build.gradle.LibraryExtension ->
                    androidExt.compileSdk = 36
                else -> throw GradleException(
                    "onnxruntime: could not raise compileSdk — android " +
                    "extension is ${androidExt?.javaClass?.name ?: "missing"}")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
