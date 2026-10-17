# UCFS

> Note: project under heavy development!

Please, see [documentation](https://formallanguageconstrainedpathquerying.github.io/UCFS/) for details.

## What is UCFS?

UCFS is an **U**niversal **C**ontext-**F**ree **S**olver: a GLL‑based tool for problems at the intersection of context‑free languages 
over edge‑labeled directed graphs. Examples of such problems:

- Parsing
- Context-free path querying (CFPQ)
- Context-free language reachability (CFL-R)
- static code analysis 

**Highlights**

* Kotlin implementation with a concise Grammar DSL (EBNF‑friendly).
* Input: arbitrary edge‑labeled directed graphs.
* Output: SPPF -- finite structure for all‑paths queries.



### Repository layout (high‑level)
```
docs/         # documentation pages  
generator/    # Parser & AST node‑class generator <in progress>
solver/       # Core UCFS logic (GLL + RSM)
test-shared/  # Testcases, grammars, inputs, ANTLR4 comparison
              # grammar examples and experiments
```

### Requirements
- JDK 11+ (toolchain targets 11).  
- Gradle Wrapper included (`./gradlew`).

### Typical workflow
1) **Describe grammar** in Kotlin DSL.  
2) **Load graph** (for now `dot` format is supported).  
3) **Run query**.  
4) **Inspect results**.

### Local publishing
Publish the `solver` and `generator` jars (with POMs) to the local Maven repository, without any
tokens. Gradle itself must run on JDK 21 (`JAVA_HOME`), and a JDK 11 must also be installed locally
because the modules are compiled with a JDK 11 toolchain (it is not downloaded automatically):
```shell
JAVA_HOME=/path/to/jdk-21 ./gradlew publishToMavenLocal
# or into a separate repository instead of ~/.m2:
JAVA_HOME=/path/to/jdk-21 ./gradlew publishToMavenLocal -Dmaven.repo.local=/path/to/repo
```
Coordinates (the version is set by `ucfsVersion` in `gradle.properties`, not by git tags):
- `org.ucfs:solver:0.1.0-ai-SNAPSHOT`
- `org.ucfs:generator:0.1.0-ai-SNAPSHOT`

Every jar manifest records the commit it was built from (`UCFS-Commit`) and whether tracked files
had uncommitted changes (`UCFS-Dirty: true|false`):
```shell
unzip -p ~/.m2/repository/org/ucfs/solver/0.1.0-ai-SNAPSHOT/solver-0.1.0-ai-SNAPSHOT.jar META-INF/MANIFEST.MF
```
To get the version from git tags (axion-release) instead, pass `-PucfsVersion=`.


## Core Algorithm
UCFS is based on Generalized LL (GLL) parsing algorithm modified to handle language specification in form of Recursive State Machines (RSM) and input in form of arbitratry directed edge-labelled graph. Basic ideas described [here](https://arxiv.org/pdf/2312.11925.pdf). 
