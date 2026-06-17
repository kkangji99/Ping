// ── 브랜드 한/영 교차 검색 유틸 ──────────────────────────────────────────────

// key: 정규화된 영어 (소문자·공백제거), value: 한국어 표기 목록
const _brandAliases = <String, List<String>>{
  'zara':              ['자라']
, 'hm':               ['에이치앤엠', 'h&m']
, 'nike':             ['나이키']
, 'adidas':           ['아디다스']
, 'uniqlo':           ['유니클로']
, 'gu':               ['지유']
, 'muji':             ['무인양품']
, 'gap':              ['갭']
, 'innisfree':        ['이니스프리']
, 'oliveyoung':       ['올리브영']
, 'laneige':          ['라네즈']
, 'sulwhasoo':        ['설화수']
, 'etude':            ['에뛰드']
, 'missha':           ['미샤']
, 'thefaceshop':      ['더페이스샵']
, 'naturerepublic':   ['네이처리퍼블릭']
, 'amorepacific':     ['아모레퍼시픽']
, 'starbucks':        ['스타벅스']
, 'twosome':          ['투썸플레이스']
, 'ediyacoffee':      ['이디야커피', '이디야']
, 'parisbaguette':    ['파리바게트']
, 'touslesjours':     ['뚜레쥬르']
, 'mcdonalds':        ['맥도날드']
, 'burgerking':       ['버거킹']
, 'lotteria':         ['롯데리아']
, 'momstouch':        ['맘스터치']
, 'subway':           ['서브웨이']
, 'gs25':             ['지에스25', '지에스 25']
, 'cu':               ['씨유']
, 'seveneleven':      ['세븐일레븐']
, 'ministop':         ['미니스톱']
, 'emart':            ['이마트']
, 'topten':           ['탑텐']
, 'spao':             ['스파오']
, 'musinsa':          ['무신사']
, 'eland':            ['이랜드']
, 'newbalance':       ['뉴발란스']
, 'thenorthface':     ['노스페이스']
, 'columbia':         ['컬럼비아']
, 'kolon':            ['코오롱', '코오롱스포츠']
, 'fila':             ['휠라']
, 'puma':             ['푸마']
, 'reebok':           ['리복']
, 'amuse':            ['에뮤드']
};

/// 검색어가 이름과 매칭되는지 확인 (한↔영 별칭 포함)
bool matchesBrandSearch(String itemName, String query) {
  if (query.isEmpty) return true;
  final q    = query.toLowerCase().replaceAll(' ', '');
  final name = itemName.toLowerCase();

  // 이름 직접 포함
  if (name.contains(q) || name.replaceAll(' ', '').contains(q)) return true;

  // 영어 쿼리 → 한국어 별칭 체크 / 한국어 쿼리 → 영어 별칭 체크
  for (final entry in _brandAliases.entries) {
    final engKey = entry.key;
    final koList = entry.value;

    // 영어로 검색 → 해당 한국어 이름 매칭
    if (engKey.contains(q) || q.contains(engKey)) {
      for (final ko in koList) {
        if (name.contains(ko.toLowerCase())) return true;
      }
    }

    // 한국어로 검색 → 해당 영어 이름 매칭
    for (final ko in koList) {
      if (ko.toLowerCase().contains(q)) {
        if (name.replaceAll(' ', '').contains(engKey)) return true;
      }
    }
  }
  return false;
}
