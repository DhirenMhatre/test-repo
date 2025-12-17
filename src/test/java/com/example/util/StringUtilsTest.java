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
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import org.junit.jupiter.params.provider.Arguments;

@ExtendWith(MockitoExtension.class)
@DisplayName("StringUtils Tests")
class StringUtilsTest {

    @InjectMocks
    private StringUtils stringUtils;

    private StringUtils spyUtils;

    @Mock
    private Runnable mockRunnable;

    @BeforeEach
    void setUp() {
        spyUtils = spy(stringUtils);
    }

    @AfterEach
    void tearDown() {
        stringUtils = null;
        spyUtils = null;
    }

    // --------------------------
    // isEmpty tests
    // --------------------------

    static Stream<Arguments> provideEmptyStrings() {
        return Stream.of(
                Arguments.of((String) null),
                Arguments.of(""),
                Arguments.of(" "),
                Arguments.of("   "),
                Arguments.of("\t"),
                Arguments.of("\n"),
                Arguments.of(" \t \n ")
        );
    }

    @ParameterizedTest(name = "isEmpty should return true for \"{0}\"")
    @MethodSource("provideEmptyStrings")
    @DisplayName("isEmpty - returns true for null or whitespace-only strings")
    void testIsEmpty_WithNullOrWhitespace_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {"a", "abc", "  abc  ", "0", "foo bar"})
    @DisplayName("isEmpty - returns false for non-empty strings")
    void testIsEmpty_WithNonEmpty_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    @Test
    @DisplayName("isEmpty - Mockito mock usage demonstration")
    void testIsEmpty_WithMockUsage_ShouldInvokeRunnableWhenEmpty() {
        boolean empty = stringUtils.isEmpty("   ");
        if (empty) {
            mockRunnable.run();
        }
        verify(mockRunnable, times(1)).run();
    }

    // --------------------------
    // reverse tests
    // --------------------------

    static Stream<Arguments> provideStringsForReverse() {
        return Stream.of(
                Arguments.of("", ""),
                Arguments.of("a", "a"),
                Arguments.of("ab", "ba"),
                Arguments.of("abc", "cba"),
                Arguments.of("racecar", "racecar"),
                Arguments.of(" Hello ", " olleH ")
        );
    }

    @ParameterizedTest(name = "reverse(\"{0}\") should be \"{1}\"")
    @MethodSource("provideStringsForReverse")
    @DisplayName("reverse - reverses strings correctly")
    void testReverse_WithVariousInputs_ShouldReverseCorrectly(String input, String expected) {
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("reverse - returns null when input is null")
    void testReverse_WithNull_ShouldReturnNull() {
        assertNull(stringUtils.reverse(null));
    }

    // --------------------------
    // isPalindrome tests
    // --------------------------

    @Test
    @DisplayName("isPalindrome - returns false for null")
    void testIsPalindrome_WithNull_ShouldReturnFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "racecar",
            "RaceCar",
            "nurses run",
            "A man a plan a canal Panama",
            "abba",
            "Able was I ere I saw Elba"
    })
    @DisplayName("isPalindrome - returns true for palindromic strings ignoring spaces and case")
    void testIsPalindrome_WithPalindromes_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isPalindrome(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "hello",
            "ab",
            "abc",
            "abca",
            "A man, a plan, a canal, Panama" // punctuation not ignored by implementation
    })
    @DisplayName("isPalindrome - returns false for non-palindromes")
    void testIsPalindrome_WithNonPalindromes_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isPalindrome(input));
    }

    // --------------------------
    // countWords tests
    // --------------------------

    static Stream<Arguments> provideStringsForCountWords() {
        return Stream.of(
                Arguments.of("Hello", 1),
                Arguments.of("  Hello  ", 1),
                Arguments.of("Hello world", 2),
                Arguments.of(" one  two\tthree\n", 3),
                Arguments.of("   a   b   c   ", 3),
                Arguments.of("中文 测试", 2),
                Arguments.of("tabs\tand\nnewlines mixed", 3)
        );
    }

    @ParameterizedTest(name = "countWords(\"{0}\") should be 0")
    @MethodSource("provideEmptyStrings")
    @DisplayName("countWords - returns 0 for null or whitespace-only strings")
    void testCountWords_WithNullOrWhitespace_ShouldReturnZero(String input) {
        assertEquals(0, stringUtils.countWords(input));
    }

    @ParameterizedTest(name = "countWords(\"{0}\") should be {1}")
    @MethodSource("provideStringsForCountWords")
    @DisplayName("countWords - counts words separated by whitespace")
    void testCountWords_WithVariousInputs_ShouldReturnExpectedCount(String input, int expected) {
        assertEquals(expected, stringUtils.countWords(input));
    }

    @Test
    @DisplayName("countWords - delegates to isEmpty (verified via spy)")
    void testCountWords_DelegatesToIsEmpty_UsingSpy() {
        String input = "   ";
        int result = spyUtils.countWords(input);
        assertEquals(0, result);
        verify(spyUtils, times(1)).isEmpty(input);
    }

    @Test
    @DisplayName("countWords - propagates exception from isEmpty (assertThrows)")
    void testCountWords_WhenIsEmptyThrows_ShouldPropagateException() {
        String input = "boom";
        doThrow(new RuntimeException("boom")).when(spyUtils).isEmpty(input);
        assertThrows(RuntimeException.class, () -> spyUtils.countWords(input));
        verify(spyUtils, times(1)).isEmpty(input);
    }

    // --------------------------
    // Constructor test
    // --------------------------

    @Test
    @DisplayName("Constructor - should create instance")
    void testConstructor_ShouldCreateInstance() {
        StringUtils instance = new StringUtils();
        assertNotNull(instance);
    }
}