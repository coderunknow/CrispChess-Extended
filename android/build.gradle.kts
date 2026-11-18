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
// so the module is raised to the app's compileSdk here, after its own
// evaluation, without touching the package.
subprojects {
    afterEvaluate {
        if (name == "onnxruntime") {
            (extensions.findByName("android")
                as? com.android.build.gradle.LibraryExtension)?.apply {
                compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
