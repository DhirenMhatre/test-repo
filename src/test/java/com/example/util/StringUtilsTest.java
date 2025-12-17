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
import org.junit.jupiter.params.provider.Arguments;
import org.mockito.InjectMocks;
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
    private StringUtils spyStringUtils;

    @BeforeEach
    void setUp() {
        assertNotNull(stringUtils, "StringUtils should be initialized by Mockito @InjectMocks");
        assertNotNull(spyStringUtils, "Spy StringUtils should be initialized by Mockito @Spy");
    }

    @AfterEach
    void tearDown() {
        stringUtils = null;
        spyStringUtils = null;
    }

    static Stream<Arguments> blankStringsProvider() {
        return Stream.of(
                Arguments.of((String) null),
                Arguments.of(""),
                Arguments.of(" "),
                Arguments.of("   "),
                Arguments.of("\t"),
                Arguments.of("\n"),
                Arguments.of("\r\n"),
                Arguments.of(" \t\n ")
        );
    }

    static Stream<Arguments> reverseCasesProvider() {
        return Stream.of(
                Arguments.of("", ""),
                Arguments.of("a", "a"),
                Arguments.of("ab", "ba"),
                Arguments.of("racecar", "racecar"),
                Arguments.of("Hello world!", "!dlrow olleH"),
                Arguments.of("𝄞a", "a𝄞"),
                Arguments.of("a😀", "😀a"),
                Arguments.of("😀", "😀")
        );
    }

    static Stream<Arguments> palindromeCasesProvider() {
        return Stream.of(
                Arguments.of("", true),
                Arguments.of("a", true),
                Arguments.of("aa", true),
                Arguments.of("aba", true),
                Arguments.of("Aba", true),
                Arguments.of("Never odd or even", true), // spaces ignored, case-insensitive
                Arguments.of("Was it a car or a cat I saw", true),
                Arguments.of("No lemon no melon", true),
                Arguments.of("ab", false),
                Arguments.of("abc", false),
                Arguments.of("hello", false),
                Arguments.of("Not a palindrome", false)
        );
    }

    static Stream<Arguments> countWordsCasesProvider() {
        return Stream.of(
                Arguments.of((String) null, 0),
                Arguments.of("", 0),
                Arguments.of("   ", 0),
                Arguments.of("one", 1),
                Arguments.of(" one ", 1),
                Arguments.of("one two", 2),
                Arguments.of(" one  two  three ", 3),
                Arguments.of("one\ttwo\nthree", 3),
                Arguments.of(" one\t two \n three ", 3),
                Arguments.of("multiple    spaces   here", 3)
        );
    }

    @ParameterizedTest
    @MethodSource("blankStringsProvider")
    @DisplayName("isEmpty: null or whitespace-only strings should be empty")
    void testIsEmpty_BlankInputs_ReturnsTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {"a", "abc", "  a  ", "0", "text\n"})
    @DisplayName("isEmpty: non-blank strings should not be empty")
    void testIsEmpty_NonBlankInputs_ReturnsFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    @Test
    @DisplayName("reverse: null input should return null")
    void testReverse_NullInput_ReturnsNull() {
        assertNull(stringUtils.reverse(null));
    }

    @ParameterizedTest
    @MethodSource("reverseCasesProvider")
    @DisplayName("reverse: various inputs should return reversed string")
    void testReverse_VariousInputs_ReturnsReversed(String input, String expected) {
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("isPalindrome: null input should return false")
    void testIsPalindrome_NullInput_ReturnsFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @ParameterizedTest
    @MethodSource("palindromeCasesProvider")
    @DisplayName("isPalindrome: various inputs should return expected results")
    void testIsPalindrome_VariousInputs_ReturnsExpected(String input, boolean expected) {
        assertEquals(expected, stringUtils.isPalindrome(input));
    }

    @ParameterizedTest
    @MethodSource("countWordsCasesProvider")
    @DisplayName("countWords: handles null, blank, and various whitespace correctly")
    void testCountWords_VariousSpacing_ReturnsCorrectCount(String input, int expectedCount) {
        assertEquals(expectedCount, stringUtils.countWords(input));
    }

    @Test
    @DisplayName("countWords: should delegate to isEmpty (verify interaction via spy)")
    void testCountWords_DelegatesToIsEmpty_VerifyInvocation() {
        String input = " one two ";
        int result = spyStringUtils.countWords(input);
        assertEquals(2, result);
        verify(spyStringUtils, times(1)).isEmpty(input);
    }

    @Test
    @DisplayName("countWords: when isEmpty throws, exception should propagate")
    void testCountWords_WhenIsEmptyThrows_ShouldPropagateException() {
        doThrow(new IllegalStateException("forced")).when(spyStringUtils).isEmpty(any());
        assertThrows(IllegalStateException.class, () -> spyStringUtils.countWords("text"));
        verify(spyStringUtils, times(1)).isEmpty("text");
    }
}