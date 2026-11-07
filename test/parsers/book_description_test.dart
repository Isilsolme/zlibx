import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/core/book_description.dart';

void main() {
  group('normalizedBookDescription', () {
    test('strips <p> tags, keeps paragraphs (三体 device report)', () {
      const html =
          '<p>《三体》是刘慈欣创作的系列长篇科幻小说，由《三体》、《三体II·黑暗森林》、《三体III·死神永生》组成，第一部于2006年5月起在《科幻世界》杂志上连载，第二部于2008年5月首次出版，第三部则于2010年11月出版。</p><p>作品讲述了地球人类文明和三体文明的信息交流、生死搏杀及两个文明在宇宙中的兴衰历程。其第一部经过刘宇昆翻译后获得了第73届雨果奖最佳长篇小说奖 [1]&nbsp;。</p>';
      expect(
        normalizedBookDescription(html),
        '《三体》是刘慈欣创作的系列长篇科幻小说，由《三体》、《三体II·黑暗森林》、《三体III·死神永生》组成，第一部于2006年5月起在《科幻世界》杂志上连载，第二部于2008年5月首次出版，第三部则于2010年11月出版。\n\n作品讲述了地球人类文明和三体文明的信息交流、生死搏杀及两个文明在宇宙中的兴衰历程。其第一部经过刘宇昆翻译后获得了第73届雨果奖最佳长篇小说奖 [1]。',
      );
    });

    test('turns <br><br> into paragraph breaks (别想太多啦 device report)',
        () {
      const html =
          '后悔的次数愈多，就愈能成为诚实的人。顺境也好，逆境也好。<br><br>★听日本超人气“傻和尚”讲讲生活禅<br>日本备受喜爱的治愈禅师，最擅长说故事，让人的烦恼不知不觉间被化解。';
      expect(
        normalizedBookDescription(html),
        '后悔的次数愈多，就愈能成为诚实的人。顺境也好，逆境也好。\n\n★听日本超人气“傻和尚”讲讲生活禅 日本备受喜爱的治愈禅师，最擅长说故事，让人的烦恼不知不觉间被化解。',
      );
    });

    test('a lone <br> is a soft break, not a paragraph (底层逻辑 device report)',
        () {
      const html =
          '内容简介·····<br><p>“底层逻辑”来源于不同中的相同，变化背后的不变。<br></p><p>在本书中，中国著名商业顾问刘润把在《5分钟商学院》中讲述的底层逻辑的内容做了总结。</p>';
      expect(
        normalizedBookDescription(html),
        '内容简介····· “底层逻辑”来源于不同中的相同，变化背后的不变。\n\n在本书中，中国著名商业顾问刘润把在《5分钟商学院》中讲述的底层逻辑的内容做了总结。',
      );
    });

    test('stray space before a closing CJK punctuation mark is dropped', () {
      // Regression test for build #58: the old code used replaceAll with
      // a "$1" replacement, which Dart inserts literally instead of
      // interpolating the captured group.
      expect(normalizedBookDescription('A 。 B'), 'A。 B');
      expect(normalizedBookDescription('x [1] 。'), 'x [1]。');
    });

    test('decodes named and numeric entities', () {
      expect(
        normalizedBookDescription('A &amp; B &hellip; &#39;quoted&#x27;'),
        'A & B … \'quoted\'',
      );
      // "&amp;lt;" decodes to "&lt;", not "<".
      expect(normalizedBookDescription('&amp;lt;tag&amp;gt;'), '&lt;tag&gt;');
    });

    test('tags are matched case-insensitively', () {
      expect(
        normalizedBookDescription('<P>One</P><BR><P>Two</P>'),
        'One\n\nTwo',
      );
    });

    test('missing descriptions stay absent', () {
      expect(normalizedBookDescription(null), isNull);
      expect(normalizedBookDescription(''), isNull);
      expect(normalizedBookDescription('   '), isNull);
      expect(normalizedBookDescription('null'), isNull);
      expect(normalizedBookDescription('  NULL  '), isNull);
      expect(normalizedBookDescription('<p></p><br>'), isNull);
    });
  });
}
