plugins {
    id("java")
    id("jacoco")
    id("jacoco-report-aggregation")
    kotlin("jvm") version "2.4.0" apply false
    kotlin("plugin.allopen") version "2.4.0" apply false
    id("maven-publish")
    id("pl.allegro.tech.build.axion-release") version "1.21.2"
}

// Part of test code coverage report
jacoco {
    toolVersion = "0.8.14"
}

repositories {
    mavenCentral()
}

dependencies {
    jacocoAggregation(project(":solver"))
    jacocoAggregation(project(":generator"))
    jacocoAggregation(project(":test-shared"))
}

tasks.testCodeCoverageReport {
    reports {
        xml.required.set(true)
        html.required.set(true)
        csv.required.set(true)
    }
    classDirectories.setFrom(classDirectories.filter { !it.path.contains("test-shared") })
}

tasks.jacocoTestCoverageVerification {
    dependsOn(tasks.testCodeCoverageReport)

    executionData.setFrom(tasks.testCodeCoverageReport.map { it.executionData })
    sourceDirectories.setFrom(tasks.testCodeCoverageReport.map { it.sourceDirectories })
    classDirectories.setFrom(tasks.testCodeCoverageReport.map { it.classDirectories })

    violationRules {
        rule {
            isEnabled = true
            limit {
                counter = "INSTRUCTION"
                value = "COVEREDRATIO"
                minimum = "0.95".toBigDecimal()
            }
            limit {
                counter = "BRANCH"
                value = "COVEREDRATIO"
                minimum = "0.80".toBigDecimal()
            }
            limit {
                counter = "LINE"
                value = "COVEREDRATIO"
                minimum = "0.80".toBigDecimal()
            }
            limit {
                counter = "METHOD";
                value = "COVEREDRATIO"
                minimum = "0.85".toBigDecimal()
            }
            limit {
                counter = "CLASS"
                value = "COVEREDRATIO"
                minimum = "0.90".toBigDecimal()
            }
        }
    }
}

// Part of publishing

group = "org.ucfs"

// The version comes from `ucfsVersion` in gradle.properties, so it does not depend on which git
// tags are present in the clone. Pass `-PucfsVersion=` (empty) to fall back to the axion-release
// version computed from tags (the upstream release flow).
version = providers.gradleProperty("ucfsVersion")
    .map { it.trim() }
    .filter { it.isNotEmpty() }
    .orElse(provider { scmVersion.version })
    .get()

// Git state recorded in every jar manifest: the commit and whether tracked files were modified
// (untracked files such as generated sources do not count).
fun gitOutput(vararg args: String): String? = try {
    val result = providers.exec {
        commandLine("git", *args)
        isIgnoreExitValue = true
    }
    if (result.result.get().exitValue == 0) result.standardOutput.asText.get().trim() else null
} catch (e: Exception) {
    null
}

val ucfsCommit: String = gitOutput("rev-parse", "HEAD") ?: "unknown"
val ucfsDirty: String = gitOutput("status", "--porcelain", "--untracked-files=no")
    ?.let { it.isNotEmpty().toString() } ?: "unknown"

// Published modules are declared in the root project (see `publishing` below), so subprojects
// need the same coordinates; otherwise `project(":solver")` ends up in the generator POM as
// `ucfs:solver:unspecified`.
subprojects {
    group = rootProject.group
    version = rootProject.version

    tasks.withType<Jar>().configureEach {
        manifest {
            attributes(
                "Implementation-Title" to project.name,
                "Implementation-Version" to project.version.toString(),
                "UCFS-Commit" to ucfsCommit,
                "UCFS-Dirty" to ucfsDirty,
            )
        }
    }
}

evaluationDependsOnChildren()

publishing {
    publications {
        create<MavenPublication>("solver") {
            artifactId = "solver"
            from(project(":solver").components.getByName("java"))
        }
        create<MavenPublication>("generator") {
            artifactId = "generator"
            from(project(":generator").components.getByName("java"))
        }
    }
    repositories {
        maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/FormalLanguageConstrainedPathQuerying/UCFS")
            credentials {
                username = System.getenv("GITHUB_ACTOR")
                password = System.getenv("GITHUB_TOKEN")
            }
        }
    }
}
