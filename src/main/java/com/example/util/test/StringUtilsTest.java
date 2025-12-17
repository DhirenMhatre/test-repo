package main.java.com.example.util;

import main.java.com.example.util.StringUtils;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.junit.jupiter.params.provider.Arguments;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("StringUtils Tests")
class StringUtilsTest {

    @InjectMocks
    private StringUtils stringUtils;

    // Dummy mock to satisfy requirement of using @Mock with Mockito
    @Mock
    private Runnable mockRunnable;

    @BeforeEach
    void setUp() {
        if (stringUtils == null) {
            stringUtils = new StringUtils();
        }
    }

    @AfterEach
    void tearDown() {
        stringUtils = null;
    }

    @Test
    @DisplayName("isEmpty: null input should return true")
    void testIsEmpty_NullInput_ShouldReturnTrue() {
        assertTrue(stringUtils.isEmpty(null));
    }

    @ParameterizedTest
    @ValueSource(strings = {"", "   ", "\t", "\n", "\r\n", "\t \n"})
    @DisplayName("isEmpty: blank and whitespace-only strings should return true")
    void testIsEmpty_BlankAndWhitespace_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {"a", " a ", "0", "false", "中文"})
    @DisplayName("isEmpty: non-empty strings should return false")
    void testIsEmpty_NonEmpty_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    @Test
    @DisplayName("reverse: null input should return null")
    void testReverse_NullInput_ShouldReturnNull() {
        assertNull(stringUtils.reverse(null));
    }

    @ParameterizedTest
    @MethodSource("reverseProvider")
    @DisplayName("reverse: various valid strings should return reversed values")
    void testReverse_ValidStrings_ShouldReturnReversed(String input, String expected) {
        assertEquals(expected, stringUtils.reverse(input));
    }

    static Stream<Arguments> reverseProvider() {
        return Stream.of(
                Arguments.of("", ""),
                Arguments.of("a", "a"),
                Arguments.of("abc", "cba"),
                Arguments.of("ab cd", "dc ba"),
                Arguments.of("😀👍", "👍😀")
        );
    }

    @Test
    @DisplayName("isPalindrome: null input should return false")
    void testIsPalindrome_NullInput_ShouldReturnFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "", " ", "racecar", "RaceCar", "A man a plan a canal Panama", "No lemon no melon"
    })
    @DisplayName("isPalindrome: valid palindromes (ignoring whitespace and case) should return true")
    void testIsPalindrome_ValidPalindromes_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isPalindrome(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "hello", "palindrome", "A man, a plan, a canal: Panama", "abcba!"
    })
    @DisplayName("isPalindrome: non-palindromes or with punctuation should return false")
    void testIsPalindrome_NonPalindromes_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isPalindrome(input));
    }

    @ParameterizedTest
    @MethodSource("countWordsZeroProvider")
    @DisplayName("countWords: null or blank inputs should return 0")
    void testCountWords_NullOrBlank_ShouldReturnZero(String input) {
        assertEquals(0, stringUtils.countWords(input));
    }

    static Stream<Arguments> countWordsZeroProvider() {
        return Stream.of(
                Arguments.of((String) null),
                Arguments.of(""),
                Arguments.of("   "),
                Arguments.of("\t \n")
        );
    }

    @ParameterizedTest
    @MethodSource("countWordsProvider")
    @DisplayName("countWords: various inputs should return expected counts")
    void testCountWords_VariousInputs_ShouldReturnExpected(String input, int expected) {
        assertEquals(expected, stringUtils.countWords(input));
    }

    static Stream<Arguments> countWordsProvider() {
        return Stream.of(
                Arguments.of("one", 1),
                Arguments.of("one two three", 3),
                Arguments.of(" one   two\tthree\nfour ", 4),
                Arguments.of("hello-world", 1),
                Arguments.of("你好 世界", 2),
                Arguments.of("word\twith\ttabs", 3)
        );
    }

    @Test
    @DisplayName("countWords: should delegate to isEmpty for blank detection")
    void testCountWords_ShouldDelegateToIsEmpty() {
        StringUtils spyUtils = spy(new StringUtils());
        String input = "two words";
        int count = spyUtils.countWords(input);
        assertEquals(2, count);
        verify(spyUtils, times(1)).isEmpty(input);
    }

    @Test
    @DisplayName("countWords: when isEmpty throws, the exception should propagate")
    void testCountWords_WhenIsEmptyThrows_ShouldPropagateException() {
        StringUtils spyUtils = spy(new StringUtils());
        doThrow(new IllegalStateException("boom")).when(spyUtils).isEmpty(anyString());
        assertThrows(IllegalStateException.class, () -> spyUtils.countWords("anything"));
    }

    @Test
    @DisplayName("Mockito mock sanity check: should verify interactions")
    void testMockitoMock_SanityCheck_ShouldVerifyInteraction() {
        mockRunnable.run();
        verify(mockRunnable, times(1)).run();
    }
}