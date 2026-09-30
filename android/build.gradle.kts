import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.dsl.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // 国内加速镜像（官方源不可达时兜底）
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    }
}

// 强制所有子项目（含插件）的 buildscript 也使用阿里云镜像
subprojects {
    buildscript {
        repositories {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
            maven { url = uri("https://maven.aliyun.com/repository/central") }
            maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
            google()
            mavenCentral()
            gradlePluginPortal()
        }
    }

    // 禁用所有子项目的 lint 检查（避免插件 lint 任务初始化失败）
    afterEvaluate {
        extensions.findByType(ApplicationExtension::class.java)?.lint {
            abortOnError = false
            checkReleaseBuilds = false
        }
        extensions.findByType(LibraryExtension::class.java)?.lint {
            abortOnError = false
            checkReleaseBuilds = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(layout.buildDirectory)
}
