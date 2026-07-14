import org.cyclonedx.gradle.CyclonedxAggregateTask
import org.cyclonedx.gradle.CyclonedxDirectTask
import org.cyclonedx.gradle.CyclonedxPlugin

initscript {
    repositories {
        gradlePluginPortal()
    }
    dependencies {
        classpath("org.cyclonedx.bom:org.cyclonedx.bom.gradle.plugin:3.2.4")
    }
}

rootProject {
    apply<CyclonedxPlugin>()

    allprojects {
        tasks.withType<CyclonedxDirectTask>().configureEach {
            includeConfigs.set(listOf("releaseRuntimeClasspath"))
            xmlOutput.unsetConvention()
        }
    }

    tasks.withType<CyclonedxAggregateTask>().configureEach {
        xmlOutput.unsetConvention()
    }
}
