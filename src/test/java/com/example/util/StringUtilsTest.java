package com.example.util;

import com.example.util.StringUtils;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.junit.jupiter.params.provider.Arguments;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("StringUtils Tests")
class StringUtilsTest {

    @InjectMocks
    private StringUtils stringUtils;

    @Spy
    private StringUtils stringUtilsSpy;

    @Mock
    private Runnable mockRunnable;

    @BeforeEach
    void setUp() {
        // Setup if needed before each test
    }

    @AfterEach
    void tearDown() {
        // Teardown/reset mocks/spies after each test
        reset(stringUtilsSpy, mockRunnable);
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {" ", "\t", "\n", " \r\n "})
    @DisplayName("isEmpty: null or whitespace-only -> true")
    void testIsEmpty_WithNullAndWhitespace_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {"a", " abc ", "0", "text"})
    @DisplayName("isEmpty: non-blank strings -> false")
    void testIsEmpty_WithNonBlank_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    @Test
    @DisplayName("reverse: null -> null")
    void testReverse_WithNull_ShouldReturnNull() {
        assertNull(stringUtils.reverse(null));
    }

    @Test
    @DisplayName("reverse: empty string -> empty string")
    void testReverse_WithEmptyString_ShouldReturnEmptyString() {
        assertEquals("", stringUtils.reverse(""));
    }

    @ParameterizedTest
    @MethodSource("provideReverseCases")
    @DisplayName("reverse: standard strings -> reversed correctly")
    void testReverse_WithStandardString_ShouldReturnReversed(String input, String expected) {
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("reverse: preserves emoji surrogate pairs order")
    void testReverse_WithEmoji_ShouldPreserveEmojiAndOrder() {
        String input = "A😊B";
        String expected = "B😊A";
        assertEquals(expected, stringUtils.reverse(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "madam",
            "RaceCar",
            "A man a plan a canal Panama",
            "Never odd or even"
    })
    @DisplayName("isPalindrome: palindromic inputs -> true")
    void testIsPalindrome_WithPalindromeInputs_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isPalindrome(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {"hello", "Java", "OpenAI", "abc"})
    @DisplayName("isPalindrome: non-palindromic inputs -> false")
    void testIsPalindrome_WithNonPalindromeInputs_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isPalindrome(input));
    }

    @Test
    @DisplayName("isPalindrome: null -> false")
    void testIsPalindrome_WithNull_ShouldReturnFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {" ", "\t", "\n", "   "})
    @DisplayName("countWords: null or blank -> 0")
    void testCountWords_WithNullAndBlank_ShouldReturnZero(String input) {
        assertEquals(0, stringUtils.countWords(input));
    }

    @Test
    @DisplayName("countWords: multiple whitespaces -> correct count")
    void testCountWords_WithMultipleSpaces_ShouldCountCorrectly() {
        assertEquals(3, stringUtils.countWords("  two   words\nhere "));
    }

    @Test
    @DisplayName("countWords: punctuation separated by whitespace -> word count by whitespace")
    void testCountWords_WithPunctuation_ShouldCountWordsSeparatedByWhitespace() {
        assertEquals(2, stringUtils.countWords("Hello, world!"));
    }

    @ParameterizedTest
    @MethodSource("wordCountProvider")
    @DisplayName("countWords: various inputs -> expected counts")
    void testCountWords_VariousInputs_ShouldReturnExpected(String input, int expected) {
        assertEquals(expected, stringUtils.countWords(input));
    }

    @Test
    @DisplayName("countWords: verifies internal call to isEmpty using spy")
    void testCountWords_ShouldCallIsEmptyInternally() {
        String input = "   ";
        int result = stringUtilsSpy.countWords(input);
        assertEquals(0, result);
        verify(stringUtilsSpy, times(1)).isEmpty(input);
    }

    @Test
    @DisplayName("reverse: stubbed spy throws exception -> assertThrows")
    void testReverse_WithStubbedSpy_ShouldThrowIllegalArgumentException() {
        doThrow(new IllegalArgumentException("boom")).when(stringUtilsSpy).reverse("throw");
        assertThrows(IllegalArgumentException.class, () -> stringUtilsSpy.reverse("throw"));
    }

    @Test
    @DisplayName("Mockito mock: verify interaction with a mocked dependency")
    void testMockitoMock_DemonstrateInteractionVerification() {
        mockRunnable.run();
        verify(mockRunnable, times(1)).run();
        verifyNoMoreInteractions(mockRunnable);
    }

    private static Stream<Arguments> provideReverseCases() {
        return Stream.of(
                Arguments.of("abc", "cba"),
                Arguments.of("racecar", "racecar"),
                Arguments.of(" ab ", " ba "),
                Arguments.of("Hello World", "dlroW olleH")
        );
    }

    private static Stream<Arguments> wordCountProvider() {
        return Stream.of(
                Arguments.of("one", 1),
                Arguments.of(" two words ", 2),
                Arguments.of("tabs\tand\nnewlines", 3),
                Arguments.of("multiple   spaces  between", 3),
                Arguments.of("Hello, world!", 2),
                Arguments.of("   ", 0),
                Arguments.of(null, 0)
        );
    }
}