package org.ucfs.input.utils


import org.ucfs.input.InputGraph
import org.ucfs.input.TerminalInputLabel
import java.lang.StringBuilder

class DotWriter {

    fun getDotView(graph: InputGraph<Int, TerminalInputLabel>, isDirected: Boolean = true): String {
        val builder = StringBuilder()
        val graphType = if (isDirected) "digraph" else "graph"
        val connector = if (isDirected) "->" else "--"

        builder.append("$graphType ${graph.name} {\n")

        for (vertex in graph.startVertices) {
            builder.append("    start $connector $vertex;\n")
        }

        for ((from, edges) in graph.edges) {
            for (edge in edges) {
                val to = edge.targetVertex
                val label = edge.label.terminal.toString()
                builder.append("    $from $connector $to [label = ${quote(label)}];\n")
            }
        }

        builder.append("}")
        return builder.toString()
    }

    /**
     * Writes a label as a DOT string: `\` becomes `\\` and `"` becomes `\"`.
     * GraphFromDotVisitor reverses this. A label ending with `\` can't be written:
     * Dot.g4 reads the closing `\"` as an escaped quote.
     */
    private fun quote(label: String): String =
        "\"" + label.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
}
