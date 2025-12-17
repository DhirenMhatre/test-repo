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

import java.util.function.Supplier;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("StringUtils Tests")
class StringUtilsTest {

    @InjectMocks
    private StringUtils stringUtils;

    @Mock
    private Supplier<String> stringSupplier;

    @BeforeEach
    void setUp() {
        stringUtils = new StringUtils();
    }

    @AfterEach
    void tearDown() {
        stringUtils = null;
    }

    // -------- Data Providers --------

    static Stream<Arguments> provideBlankStrings() {
        return Stream.of(
                Arguments.of((String) null),
                Arguments.of(""),
                Arguments.of(" "),
                Arguments.of("\t"),
                Arguments.of("\n"),
                Arguments.of(" \t \n ")
        );
    }

    static Stream<Arguments> provideReverseData() {
        return Stream.of(
                Arguments.of("", ""),
                Arguments.of("a", "a"),
                Arguments.of("ab", "ba"),
                Arguments.of("abc", "cba"),
                Arguments.of("résumé", "émusér"),
                Arguments.of("racecar", "racecar"),
                Arguments.of("  ab ", " ba  ")
        );
    }

    static Stream<Arguments> providePalindromeTrueCases() {
        return Stream.of(
                Arguments.of("madam"),
                Arguments.of("RaceCar"),
                Arguments.of("A man a plan a canal Panama"),
                Arguments.of(" "),
                Arguments.of("   ")
        );
    }

    static Stream<Arguments> providePalindromeFalseCases() {
        return Stream.of(
                Arguments.of("hello"),
                Arguments.of("abc"),
                Arguments.of("ab"),
                Arguments.of("No lemon, no melonX")
        );
    }

    static Stream<Arguments> provideCountWordsData() {
        return Stream.of(
                Arguments.of("Hello world", 2),
                Arguments.of("   leading spaces", 2),
                Arguments.of("trailing spaces   ", 2),
                Arguments.of("multiple   spaces  between   words", 4),
                Arguments.of("tabs\tand\nnewlines mixed", 4),
                Arguments.of(" one ", 1),
                Arguments.of("a b c d e", 5)
        );
    }

    // -------- isEmpty tests --------

    @ParameterizedTest
    @MethodSource("provideBlankStrings")
    @DisplayName("isEmpty: Null or blank inputs should return true")
    void testIsEmpty_NullOrBlankInputs_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {"a", " abc ", "0", "hello"})
    @DisplayName("isEmpty: Non-blank inputs should return false")
    void testIsEmpty_NonBlankInputs_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    // -------- reverse tests --------

    @Test
    @DisplayName("reverse: Null input should return null")
    void testReverse_NullInput_ShouldReturnNull() {
        assertNull(stringUtils.reverse(null));
    }

    @ParameterizedTest
    @MethodSource("provideReverseData")
    @DisplayName("reverse: Various inputs should be reversed correctly")
    void testReverse_VariousInputs_ShouldReverseCorrectly(String input, String expected) {
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("reverse: Should call supplier and reverse supplied string")
    void testReverse_WithSupplier_ShouldCallSupplierAndReverse() {
        when(stringSupplier.get()).thenReturn("abcd");

        String result = stringUtils.reverse(stringSupplier.get());

        assertEquals("dcba", result);
        verify(stringSupplier, times(1)).get();
    }

    // -------- isPalindrome tests --------

    @Test
    @DisplayName("isPalindrome: Null input should return false")
    void testIsPalindrome_NullInput_ShouldReturnFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    @ParameterizedTest
    @MethodSource("providePalindromeTrueCases")
    @DisplayName("isPalindrome: Palindromic inputs (ignoring spaces and case) should return true")
    void testIsPalindrome_PalindromicInputs_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isPalindrome(input));
    }

    @ParameterizedTest
    @MethodSource("providePalindromeFalseCases")
    @DisplayName("isPalindrome: Non-palindromic inputs should return false")
    void testIsPalindrome_NonPalindromicInputs_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isPalindrome(input));
    }

    // -------- countWords tests --------

    @ParameterizedTest
    @MethodSource("provideBlankStrings")
    @DisplayName("countWords: Null or blank inputs should return 0")
    void testCountWords_NullOrBlankInputs_ShouldReturnZero(String input) {
        assertEquals(0, stringUtils.countWords(input));
    }

    @ParameterizedTest
    @MethodSource("provideCountWordsData")
    @DisplayName("countWords: Various inputs should return correct counts")
    void testCountWords_VariousInputs_ShouldReturnExpectedCount(String input, int expectedCount) {
        assertEquals(expectedCount, stringUtils.countWords(input));
    }

    @Test
    @DisplayName("countWords: Should call isEmpty internally")
    void testCountWords_VerifyIsEmptyCalled() {
        String input = "hello world";
        StringUtils spyUtils = spy(stringUtils);

        int count = spyUtils.countWords(input);

        assertEquals(2, count);
        verify(spyUtils, times(1)).isEmpty(input);
    }

    @Test
    @DisplayName("countWords: When isEmpty throws, countWords should propagate exception")
    void testCountWords_WhenIsEmptyThrows_ShouldPropagateException() {
        String input = "a b";
        StringUtils spyUtils = spy(stringUtils);
        doThrow(new RuntimeException("boom")).when(spyUtils).isEmpty(input);

        RuntimeException ex = assertThrows(RuntimeException.class, () -> spyUtils.countWords(input));
        assertEquals("boom", ex.getMessage());
        verify(spyUtils, times(1)).isEmpty(input);
    }
}