package main.java.com.example.util;

import main.java.com.example.util.StringUtils;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.NullAndEmptySource;
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

    private StringUtils spyStringUtils;

    @Mock
    private Runnable dummyDependency;

    @BeforeEach
    void setUp() {
        spyStringUtils = spy(stringUtils);
    }

    @AfterEach
    void tearDown() {
        stringUtils = null;
        spyStringUtils = null;
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {" ", "   ", "\t", "\n", "\r\n", "\t  \n"})
    @DisplayName("isEmpty: Null or blank strings should return true")
    void testIsEmpty_NullOrBlank_ReturnsTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {"a", " a ", "0", "false", "中文", "🚀"})
    @DisplayName("isEmpty: Non-blank strings should return false")
    void testIsEmpty_NonBlank_ReturnsFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    @Test
    @DisplayName("reverse: Null input returns null and does not throw")
    void testReverse_NullInput_ReturnsNull_DoesNotThrow() {
        assertDoesNotThrow(() -> {
            String result = stringUtils.reverse(null);
            assertNull(result);
        });
    }

    @ParameterizedTest
    @MethodSource("reverseCases")
    @DisplayName("reverse: Various inputs should be correctly reversed")
    void testReverse_VariousInputs_ProducesExpected(String input, String expected) {
        assertEquals(expected, stringUtils.reverse(input));
    }

    static Stream<Arguments> reverseCases() {
        return Stream.of(
                Arguments.of("", ""),
                Arguments.of("a", "a"),
                Arguments.of("abc", "cba"),
                Arguments.of("racecar", "racecar"),
                Arguments.of("ab cd", "dc ba"),
                Arguments.of("  ", "  "),
                Arguments.of("A", "A"),
                Arguments.of("a😊b", "b😊a"),
                Arguments.of("mañana", "anañam")
        );
    }

    @ParameterizedTest
    @MethodSource("palindromeCases")
    @DisplayName("isPalindrome: Various inputs should return expected boolean")
    void testIsPalindrome_VariousInputs_ReturnsExpected(String input, boolean expected) {
        assertEquals(expected, stringUtils.isPalindrome(input));
    }

    static Stream<Arguments> palindromeCases() {
        return Stream.of(
                Arguments.of(null, false),
                Arguments.of("", true), // cleaned -> ""
                Arguments.of("   ", true), // whitespace removed -> ""
                Arguments.of("a", true),
                Arguments.of("aa", true),
                Arguments.of("ab", false),
                Arguments.of("racecar", true),
                Arguments.of("Madam", true),
                Arguments.of("A man a plan a canal Panama", true),
                // Note: punctuation is not removed by implementation
                Arguments.of("No lemon, no melon", false),
                Arguments.of("Was it a car or a cat I saw", false) // punctuation not removed -> false
        );
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {" ", "   ", "\t", "\n", "\r\n", "\t  \n"})
    @DisplayName("countWords: Null or blank strings should return 0")
    void testCountWords_NullOrBlank_ReturnsZero(String input) {
        assertEquals(0, stringUtils.countWords(input));
    }

    @ParameterizedTest
    @MethodSource("countWordsCases")
    @DisplayName("countWords: Mixed whitespace and words should return expected count")
    void testCountWords_MixedWhitespaceAndWords_ReturnsExpected(String input, int expected) {
        assertEquals(expected, stringUtils.countWords(input));
    }

    static Stream<Arguments> countWordsCases() {
        return Stream.of(
                Arguments.of("one", 1),
                Arguments.of("one two", 2),
                Arguments.of(" one   two  three ", 3),
                Arguments.of("\tone\t two\tthree\n", 3),
                Arguments.of("hello,world", 1), // no whitespace, one token
                Arguments.of("こんにちは 世界", 2),
                Arguments.of("spaces    inside", 2),
                Arguments.of("a b c d e", 5)
        );
    }

    @Test
    @DisplayName("countWords: Should invoke isEmpty internally for blank input (verified via spy)")
    void testCountWords_InvokesIsEmptyViaSpy_WhenInputBlank() {
        String blank = "   \t\n  ";
        int result = spyStringUtils.countWords(blank);
        assertEquals(0, result);
        verify(spyStringUtils, times(1)).isEmpty(blank);
    }

    @Test
    @DisplayName("Null reference: Invoking instance method on null should throw NullPointerException")
    void testMethodInvocation_OnNullReference_ShouldThrowNullPointerException() {
        StringUtils nullRef = null;
        assertThrows(NullPointerException.class, () -> nullRef.isEmpty("value"));
    }

    @Test
    @DisplayName("Mockito: Verify mock interaction works")
    void testMockitoMock_VerifyInteraction() {
        doNothing().when(dummyDependency).run();
        dummyDependency.run();
        verify(dummyDependency, times(1)).run();
        verifyNoMoreInteractions(dummyDependency);
    }
}