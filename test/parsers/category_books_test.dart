import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';

/// Category-page books, modelled on the live `/category/75/` document
/// captured 2026-11-11 (Firefox, zh.z-library.sk, saved page HTML):
/// 10 `<z-bookcard>` elements, same shape as the booklist detail
/// page's cards. The category fetch itself now uses
/// [parseCategoryBooksPage] (which keeps `deleted` cards and reads
/// the page count); this test pins that the shared
/// [parseBooklistDetailBooks] still handles category-shaped cards —
/// one synthetic `deleted="1"` card is appended: it must be skipped
/// by that parser. Every card carries a `user_token` attribute (a
/// session secret); the value here is a fake marker — the parser
/// must ignore it, and no parsed field may contain it.
const _categoryHtml = '''
<html><body><div id="searchResultBox">
<z-bookcard id="11993425" isbn="" termshash="bab11857da3b83e406fd7f7c311d8f7a" href="/book/0vp2QrWNRr/%E6%B2%88%E5%86%B0%E8%87%AA%E8%BF%B0%E6%88%91%E5%92%8C%E5%91%A8%E6%B0%B8%E5%BA%B7%E7%9A%84%E6%95%85%E4%BA%8B.html" download="/dl/fake-token-1" deleted="0" publisher="飆笛出版社" language="中文" year="2015" extension="epub" filesize="823 KB" rating="5.0" quality="4" user_token="fake-token-must-be-ignored" contenttypeparam="" class="ready">
                    <img data-src="https://s3proxy-alp2-covers.cdn-zlib.sk/covers100/collections/userbooks/a2a6c4c26ea0ffbea8e239e3dee21483a3f904a82dd2f943b3022154e60ad379.jpg">
                    <div slot="title">沈冰自述—我和周永康的故事</div>
                    <div slot="author">沈冰</div>
                    <div slot="note"></div>

                    <div slot="extend">
                                                
                                            </div>

                    
                    
                    
                                    </z-bookcard>
<z-bookcard id="16709592" isbn="9787020034109" termshash="326e5aeeadfb53cef8ae91a7cd58a6fe" href="/book/JveM5Va5vE/%E5%B0%91%E5%B9%B4%E5%87%AF%E6%AD%8C.html" download="/dl/fake-token-2" deleted="0" publisher="人民文学出版社" language="中文" year="2001" extension="mobi" filesize="251 KB" rating="3.0" quality="0" user_token="fake-token-must-be-ignored" contenttypeparam="" class="ready">
                    <img data-src="https://s3proxy-alp2-covers.cdn-zlib.sk/covers100/collections/userbooks/ea6804c0c1d97e99663c3d21b8d9c3f9ffa08fff2ec961e6f581c9c8cfd33c3a.jpg">
                    <div slot="title">少年凯歌</div>
                    <div slot="author">陈凯歌</div>
                    <div slot="note"></div>

                    <div slot="extend">
                                                
                                            </div>

                    
                    
                    
                                    </z-bookcard>
<z-bookcard id="22432755" isbn="B00YD8IYTS" termshash="326e5aeeadfb53cef8ae91a7cd58a6fe" href="/book/5R0gXrArOp/%E5%B0%91%E5%B9%B4%E5%87%AF%E6%AD%8C.html" download="/dl/fake-token-3" deleted="0" publisher="" language="中文" year="2018" extension="pdf" filesize="0.97 MB" rating="3.0" quality="0" user_token="fake-token-must-be-ignored" contenttypeparam="" class="ready">
                    <img data-src="https://s3proxy-alp2-covers.cdn-zlib.sk/covers100/collections/userbooks/940ec183215ef710954c53426997558699bee3dceac1fbe79bbffa2dd703212b.jpg">
                    <div slot="title">少年凯歌</div>
                    <div slot="author">陈凯歌</div>
                    <div slot="note"></div>

                    <div slot="extend">
                                                
                                            </div>

                    
                    
                    
                                    </z-bookcard>
<z-bookcard id="23504885" isbn="5DCE9E7D-FBD0-4857-AD90-97DDDA4FFA56" termshash="326e5aeeadfb53cef8ae91a7cd58a6fe" href="/book/yOYaegVVOk/%E5%B0%91%E5%B9%B4%E5%87%AF%E6%AD%8C.html" download="/dl/fake-token-4" deleted="0" publisher="大书库资源分享专用群" language="中文" year="2017" extension="mobi" filesize="251 KB" rating="3.0" quality="3.5" user_token="fake-token-must-be-ignored" contenttypeparam="" class="ready">
                    <img data-src="https://s3proxy-alp2-covers.cdn-zlib.sk/covers100/collections/userbooks/ea6804c0c1d97e99663c3d21b8d9c3f9ffa08fff2ec961e6f581c9c8cfd33c3a.jpg">
                    <div slot="title">少年凯歌</div>
                    <div slot="author">陈凯歌</div>
                    <div slot="note"></div>

                    <div slot="extend">
                                                
                                            </div>

                    
                    
                    
                                    </z-bookcard>
<z-bookcard id="22432754" isbn="6DF1E698-C378-4C44-9BD2-32CA7E299498" termshash="326e5aeeadfb53cef8ae91a7cd58a6fe" href="/book/qOXAenQJRk/%E5%B0%91%E5%B9%B4%E5%87%AF%E6%AD%8C.html" download="/dl/fake-token-5" deleted="0" publisher="" language="中文" year="2018" extension="mobi" filesize="288 KB" rating="3.0" quality="0" user_token="fake-token-must-be-ignored" contenttypeparam="" class="ready">
                    <img data-src="https://s3proxy-alp2-covers.cdn-zlib.sk/covers100/collections/userbooks/e1bfe7b92e74d14b352297371a5ba93c4c952ee6cf8b84b1883df1b249ae2ff9.jpg">
                    <div slot="title">少年凯歌</div>
                    <div slot="author">陈凯歌</div>
                    <div slot="note"></div>

                    <div slot="extend">
                                                
                                            </div>

                    
                    
                    
                                    </z-bookcard>
<z-bookcard id="116468823" isbn="" termshash="1268695fc510d011b739b3435393eff0" href="/book/8jm3KMy3OZ/%E9%9B%BB%E5%BD%B1%E5%BE%9E%E4%B8%8D%E5%81%9C%E6%AD%A2%E8%B3%AA%E5%95%8F.html" download="/dl/fake-token-6" deleted="0" publisher="www.huibooks.com" language="中文" year="2024" extension="pdf" filesize="35.91 MB" rating="0.0" quality="0" user_token="fake-token-must-be-ignored" contenttypeparam="" class="ready">
                    <img data-src="https://s3proxy-alp2-covers.cdn-zlib.sk/covers100/collections/userbooks/5dc686079fa6756f30456a5ace66845a21508dc8823738cb45f0ffee38a67019.jpg">
                    <div slot="title">電影從不停止質問</div>
                    <div slot="author">李滄東、全州國際電影節</div>
                    <div slot="note"></div>

                    <div slot="extend">
                                                
                                            </div>

                    
                    
                    
                                    </z-bookcard>
<z-bookcard id="115845310" isbn="" termshash="5f0005c88d226f5455d63e7f53e3aa41" href="/book/qOXgobZEvk/thomas-hamilton-jacobitism-and-the-catholic-connection.html" download="/dl/fake-token-7" deleted="0" publisher="Archive of Our Own" language="英语" year="2021" extension="epub" filesize="14.57 MB" rating="0.0" quality="5" user_token="fake-token-must-be-ignored" contenttypeparam="" class="ready">
                    <img data-src="https://s3proxy-alp2-covers.cdn-zlib.sk/covers100/collections/userbooks/21dff33c0c145e1319a1c19310473bd87ff3fc2a2fed02119c0f576e87251fff.jpg">
                    <div slot="title">Thomas Hamilton, Jacobitism and the Catholic connection</div>
                    <div slot="author">sagestreet</div>
                    <div slot="note"></div>

                    <div slot="extend">
                                                
                                            </div>

                    
                    
                    
                                    </z-bookcard>
<z-bookcard id="129299025" isbn="" termshash="" href="/book/0vprgEA8Rr/the-discovery-of-jimi-hendrix.html" download="/dl/fake-token-8" deleted="0" publisher="CREEM Magazine, LLC" language="英语" year="1973" extension="pdf" filesize="8.98 MB" rating="0.0" quality="4" user_token="fake-token-must-be-ignored" contenttypeparam="" class="ready">
                    <img data-src="/img/cover-not-exists.png">
                    <div slot="title">The Discovery of Jimi Hendrix</div>
                    <div slot="author">Chris Welch</div>
                    <div slot="note"></div>

                    <div slot="extend">
                                                
                                            </div>

                    
                    
                    
                                    </z-bookcard>
<z-bookcard id="110500874" isbn="10.1353/MIS.2017.0071" termshash="ca00318b4ac2ff235c30f49ce7c68c3b" href="/book/yRaw0rdnvQ/james-whale-the-monster-man.html" download="/dl/fake-token-9" deleted="0" publisher="University of Missouri" language="英语" year="2017" extension="pdf" filesize="3.38 MB" rating="0.0" quality="0" user_token="fake-token-must-be-ignored" contenttypeparam="" class="ready">
                    <img data-src="https://s3proxy-alp2-covers.cdn-zlib.sk/covers100/collections/scimag/763db3200b4ab0cd07f007850bb97492c0e76e92c31b61712c922f883bab190a.jpg">
                    <div slot="title">James Whale: The Monster Man</div>
                    <div slot="author">Kristine Somerville</div>
                    <div slot="note"></div>

                    <div slot="extend">
                                                
                                            </div>

                    
                    
                    
                                    </z-bookcard>
<z-bookcard id="122158122" isbn="" termshash="" href="/book/ZODYl2AbRL/the-brilliant-book-2011-dw.html" download="/dl/fake-token-10" deleted="0" publisher="" language="英语" year="2022" extension="pdf" filesize="31.09 MB" rating="0.0" quality="5" user_token="fake-token-must-be-ignored" contenttypeparam="" class="ready">
                    <img data-src="https://s3proxy-alp2-covers.cdn-zlib.sk/covers100/collections/userbooks/778a524479645e862b6c859fa8b2266c23a974080b1355f5be8887d1d5698527.jpg">
                    <div slot="title">The brilliant book 2011 : DW</div>
                    <div slot="author">Unknown</div>
                    <div slot="note"></div>

                    <div slot="extend">
                                                
                                            </div>

                    
                    
                    
                                    </z-bookcard>
<z-bookcard id="999999999" isbn="" termshash="00000000000000000000000000000000" href="/book/deletedHash123/%E5%88%A0%E9%99%A4%E7%9A%84%E4%B9%A6.html" download="/dl/fake-token-11" deleted="1" publisher="No Publisher" language="中文" year="2020" extension="epub" filesize="100 KB" rating="4.0" quality="0" user_token="fake-token-must-be-ignored" contenttypeparam="" class="ready">
<img data-src="https://s3proxy-alp2-covers.cdn-zlib.sk/covers100/deleted.jpg">
<div slot="title">Deleted Book</div>
<div slot="author">Nobody</div>
<div slot="note"></div>
<div slot="extend"></div>
</z-bookcard>
</div></body></html>
''';

const _fakeToken = 'fake-token-must-be-ignored';

List<Book> _parse() => parseBooklistDetailBooks(
  _categoryHtml,
  baseUrl: 'https://zh.z-library.sk',
);

void main() {
  group('parseBooklistDetailBooks on a category page', () {
    test('parses all 10 books with ids, titles, hashes and ratings', () {
      final books = _parse();
      expect(books.length, 10);
      expect(
        books.map((b) => b.id).toList(),
        [
          11993425,
          16709592,
          22432755,
          23504885,
          22432754,
          116468823,
          115845310,
          129299025,
          110500874,
          122158122,
        ],
      );
      final first = books.first;
      expect(first.title, '沈冰自述—我和周永康的故事');
      expect(first.author, '沈冰');
      expect(first.hash, '0vp2QrWNRr');
      expect(first.interestScore, '5.0');
      expect(first.year, 2015);
      expect(first.extension, 'epub');
      expect(first.filesizeString, '823 KB');
      expect(first.language, '中文');
      expect(first.publisher, '飆笛出版社');
      expect(
        first.cover,
        startsWith('https://s3proxy-alp2-covers.cdn-zlib.sk/'),
      );
    });

    test('an empty publisher parses to null', () {
      final books = _parse();
      expect(books[2].title, '少年凯歌');
      expect(books[2].hash, '5R0gXrArOp');
      expect(books[2].publisher, isNull);
    });

    test('a relative cover resolves against the base URL', () {
      final books = _parse();
      expect(
        books[7].cover,
        'https://zh.z-library.sk/img/cover-not-exists.png',
      );
    });

    test('a deleted="1" card is skipped', () {
      final books = _parse();
      expect(books.any((b) => b.id == 999999999), isFalse);
      expect(books.any((b) => b.title == 'Deleted Book'), isFalse);
    });

    test('the user_token attribute is ignored', () {
      final books = _parse();
      final fields = books.expand(
        (b) => [
          b.title,
          b.author,
          b.cover,
          b.hash,
          b.publisher,
          b.language,
          b.extension,
          b.filesizeString,
          b.interestScore,
        ],
      );
      expect(
        fields.any((f) => f != null && f.contains(_fakeToken)),
        isFalse,
      );
    });
  });
}
