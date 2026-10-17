package acceptance

import org.junit.jupiter.api.Test
import org.ucfs.input.DotParser
import org.ucfs.input.InputGraph
import org.ucfs.input.TerminalInputLabel
import org.ucfs.input.utils.DotWriter
import org.ucfs.rsm.symbol.Term
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * E1-S1 acceptance check: DotWriter output must be valid input for DotParser,
 * so that write -> parse gives back the same graph (start vertices and labelled edges).
 */
class E1DotWriterRoundTripTest {

    private fun graphOf(start: Set<Int>, edges: List<Triple<Int, String, Int>>): InputGraph<Int, TerminalInputLabel> {
        val graph = InputGraph<Int, TerminalInputLabel>()
        for (v in start) graph.addStartVertex(v)
        for ((from, label, to) in edges) {
            graph.addVertex(from)
            graph.addVertex(to)
            graph.addEdge(from, TerminalInputLabel(Term(label)), to)
        }
        return graph
    }

    private fun edgeSet(graph: InputGraph<Int, TerminalInputLabel>): Set<Triple<Int, Any?, Int>> =
        graph.edges.flatMap { (from, edges) ->
            edges.map { Triple(from, (it.label.terminal as Term<*>).value, it.targetVertex) }
        }.toSet()

    private fun roundTrip(graph: InputGraph<Int, TerminalInputLabel>): InputGraph<Int, TerminalInputLabel> =
        DotParser().parseDot(DotWriter().getDotView(graph))

    @Test
    fun labelValuesAreQuoted() {
        val dot = DotWriter().getDotView(graphOf(setOf(0), listOf(Triple(0, "a", 1))))
        assertTrue(dot.contains("0 -> 1 [label = \"a\"];"), "unexpected DOT:\n$dot")
    }

    @Test
    fun bracketLabelsSurviveRoundTrip() {
        val graph = graphOf(setOf(0), listOf(Triple(0, "(", 0), Triple(0, ")", 0)))
        val parsed = roundTrip(graph)
        assertEquals(setOf(0), parsed.startVertices)
        assertEquals(edgeSet(graph), edgeSet(parsed))
    }

    @Test
    fun pointsToStyleLabelsSurviveRoundTrip() {
        // Labels shaped like the ones a PAG export will produce: identifiers, digits,
        // and Soot field signatures with spaces, colons, angle and square brackets.
        val graph = graphOf(
            setOf(0, 3),
            listOf(
                Triple(0, "alloc", 1),
                Triple(1, "assign", 2),
                Triple(2, "load_f", 3),
                Triple(3, "store_<java.lang.String: char[] value>", 4),
                Triple(4, "1", 0),
                Triple(4, "with space", 5),
                Triple(5, "a->b", 0),
            )
        )
        val parsed = roundTrip(graph)
        assertEquals(setOf(0, 3), parsed.startVertices)
        assertEquals(edgeSet(graph), edgeSet(parsed))
    }

    @Test
    fun quoteInsideLabelSurvivesRoundTrip() {
        val graph = graphOf(setOf(0), listOf(Triple(0, "say \"hi\"", 1)))
        val parsed = roundTrip(graph)
        assertEquals(edgeSet(graph), edgeSet(parsed))
    }
}
