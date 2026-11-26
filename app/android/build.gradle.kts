allprojects {
    repositories {
        maven(url = "https://maven.aliyun.com/repository/google")
        maven(url = "https://maven.aliyun.com/repository/public")
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
    // 2026-11-26：jni 的 CMake 在中文路径下把「短剧」编码成乱码，
    // 产物链接到 D:\???APP\... 而 AGP 在真实路径找不到 libdartjni.so，
    // 报 "Expected output file ... but there was none"。
    //
    // 只把这一个子项目的输出挪到纯 ASCII 路径。app 保持原路径 ——
    // 否则 ops/build.ps1 里拷 app-release.apk 的路径会失效。
    if (project.name == "jni") {
        project.layout.buildDirectory.set(java.io.File("D:/djbuild/jni"))
    } else {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
