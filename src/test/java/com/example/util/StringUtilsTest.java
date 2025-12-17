package com.example.util;

import com.example.util.StringUtils;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.function.Function;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import org.junit.jupiter.params.provider.Arguments;

@ExtendWith(MockitoExtension.class)
@DisplayName("StringUtils Tests")
class StringUtilsTest {

    @InjectMocks
    private StringUtils stringUtils;

    @Spy
    private StringUtils spyStringUtils;

    @Mock
    private Function<String, String> mockTransformer;

    @BeforeEach
    void setUp() {
        // No-op setup; instance creation handled by Mockito
    }

    @AfterEach
    void tearDown() {
        stringUtils = null;
        spyStringUtils = null;
        mockTransformer = null;
    }

    // ------------------------
    // isEmpty tests
    // ------------------------

    static Stream<Arguments> provideNullOrWhitespace() {
        return Stream.of(
                Arguments.of((String) null),
                Arguments.of(""),
                Arguments.of("   "),
                Arguments.of("\t\n\r ")
        );
    }

    @ParameterizedTest
    @MethodSource("provideNullOrWhitespace")
    @DisplayName("isEmpty: null or whitespace-only -> true")
    void testIsEmpty_NullOrWhitespace_ReturnsTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {"a", " abc ", "0", "false", "hello\nworld"})
    @DisplayName("isEmpty: non-empty strings (after trim) -> false")
    void testIsEmpty_NonEmptyStrings_ReturnsFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    // ------------------------
    // reverse tests
    // ------------------------

    @Test
    @DisplayName("reverse: null -> null")
    void testReverse_Null_ReturnsNull() {
        assertNull(stringUtils.reverse(null));
    }

    @Test
    @DisplayName("reverse: empty string -> empty string")
    void testReverse_EmptyString_ReturnsEmptyString() {
        assertEquals("", stringUtils.reverse(""));
    }

    @Test
    @DisplayName("reverse: normal string -> reversed")
    void testReverse_NormalString_ReturnsReversed() {
        assertEquals("dcba", stringUtils.reverse("abcd"));
    }

    @Test
    @DisplayName("reverse: Unicode surrogate pairs (emoji) are handled")
    void testReverse_UnicodeSurrogatePairs_ReturnsProperly() {
        String input = "😀👍";
        String expected = "👍😀";
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("reverse (spy): verify method invocation")
    void testReverse_SpyMethodCalled_Verified() {
        String input = "abc";
        String expected = "cba";

        String result = spyStringUtils.reverse(input);

        assertEquals(expected, result);
        verify(spyStringUtils).reverse(input);
    }

    @Test
    @DisplayName("reverse (spy): stubbed to throw -> assertThrows")
    void testReverse_SpyStubbedThrows_ThrowsException() {
        doThrow(new IllegalArgumentException("boom")).when(spyStringUtils).reverse("boom");
        assertThrows(IllegalArgumentException.class, () -> spyStringUtils.reverse("boom"));
        verify(spyStringUtils).reverse("boom");
    }

    // ------------------------
    // isPalindrome tests
    // ------------------------

    @Test
    @DisplayName("isPalindrome: null -> false")
    void testIsPalindrome_Null_ReturnsFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @Test
    @DisplayName("isPalindrome: simple palindrome -> true")
    void testIsPalindrome_SimplePalindrome_ReturnsTrue() {
        assertTrue(stringUtils.isPalindrome("racecar"));
    }

    @Test
    @DisplayName("isPalindrome: ignores case and spaces -> true")
    void testIsPalindrome_CaseAndSpaces_Ignored_ReturnsTrue() {
        assertTrue(stringUtils.isPalindrome("Never odd or even"));
    }

    @Test
    @DisplayName("isPalindrome: non-palindrome -> false")
    void testIsPalindrome_NonPalindrome_ReturnsFalse() {
        assertFalse(stringUtils.isPalindrome("hello"));
    }

    @Test
    @DisplayName("isPalindrome: punctuation not ignored -> false for phrase with commas")
    void testIsPalindrome_PunctuationNotIgnored_ReturnsFalse() {
        assertFalse(stringUtils.isPalindrome("No lemon, no melon"));
    }

    // ------------------------
    // countWords tests
    // ------------------------

    @ParameterizedTest
    @MethodSource("provideNullOrWhitespace")
    @DisplayName("countWords: null or blank -> 0")
    void testCountWords_NullOrBlank_ReturnsZero(String input) {
        assertEquals(0, stringUtils.countWords(input));
    }

    @Test
    @DisplayName("countWords: single word -> 1")
    void testCountWords_SingleWord() {
        assertEquals(1, stringUtils.countWords("word"));
    }

    @Test
    @DisplayName("countWords: multiple words with single spaces -> correct count")
    void testCountWords_MultipleWordsWithSpaces() {
        assertEquals(3, stringUtils.countWords("one two three"));
    }

    @Test
    @DisplayName("countWords: mixed whitespace and leading/trailing -> correct count")
    void testCountWords_MixedWhitespaceAndTrim() {
        assertEquals(3, stringUtils.countWords("  one   two  three   "));
    }

    @Test
    @DisplayName("countWords: punctuation is part of tokens -> count by whitespace")
    void testCountWords_WithPunctuationCountsByWhitespace() {
        assertEquals(2, stringUtils.countWords("hello, world!"));
    }

    @Test
    @DisplayName("countWords: newlines and tabs -> correct count")
    void testCountWords_WithNewlinesAndTabs() {
        assertEquals(3, stringUtils.countWords("one\ttwo\nthree"));
    }

    // ------------------------
    // Mockito mock usage (demonstration)
    // ------------------------

    @Test
    @DisplayName("reverse: result matches mocked transformer output (mock usage)")
    void testReverse_ResultMatchesMockedTransformerOutput() {
        when(mockTransformer.apply("abc")).thenReturn("cba");

        String actual = stringUtils.reverse("abc");
        String expected = mockTransformer.apply("abc");

        assertEquals(expected, actual);
        verify(mockTransformer).apply("abc");
    }
}