import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/supabase_service.dart';
import 'admin_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _idCtrl  = TextEditingController();
  final _pwCtrl  = TextEditingController();
  bool _obscure  = true;
  bool _loading  = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<SupabaseService>().isSignedIn) _goToAdmin();
    });
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  void _goToAdmin() {
    Navigator.pushReplacement(
      context
    , MaterialPageRoute(builder: (_) => const AdminScreen())
    );
  }

  Future<void> _submit() async {
    final id = _idCtrl.text.trim();
    final pw = _pwCtrl.text;
    if (id.isEmpty || pw.isEmpty) {
      setState(() => _error = '아이디와 비밀번호를 입력해주세요.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<SupabaseService>().signIn(id, pw);
      if (mounted) _goToAdmin();
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = '아이디 또는 비밀번호가 올바르지 않습니다.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 로그인')
      , backgroundColor: Theme.of(context).colorScheme.primary
      , foregroundColor: Colors.white
      )
    , body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32)
        , child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400)
          , child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch
            , children: [
                Icon(Icons.admin_panel_settings, size: 64, color: Theme.of(context).colorScheme.primary)
              , const SizedBox(height: 24)
              , Text(
                  '관리자 로그인'
                , style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)
                , textAlign: TextAlign.center
                )
              , const SizedBox(height: 32)
              , TextField(
                  controller: _idCtrl
                , decoration: const InputDecoration(
                    labelText: '아이디'
                  , prefixIcon: Icon(Icons.person_outline)
                  , border: OutlineInputBorder()
                  )
                , keyboardType: TextInputType.emailAddress
                , textInputAction: TextInputAction.next
                )
              , const SizedBox(height: 16)
              , TextField(
                  controller: _pwCtrl
                , decoration: InputDecoration(
                    labelText: '비밀번호'
                  , prefixIcon: const Icon(Icons.lock_outline)
                  , border: const OutlineInputBorder()
                  , suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)
                    , onPressed: () => setState(() => _obscure = !_obscure)
                    )
                  )
                , obscureText: _obscure
                , textInputAction: TextInputAction.done
                , onSubmitted: (_) => _submit()
                )
              , if (_error != null) ...[
                  const SizedBox(height: 12)
                , Container(
                    padding: const EdgeInsets.all(12)
                  , decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1)
                    , borderRadius: BorderRadius.circular(8)
                    , border: Border.all(color: Colors.redAccent.withOpacity(0.3))
                    )
                  , child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13), textAlign: TextAlign.center)
                  )
                ]
              , const SizedBox(height: 24)
              , FilledButton(
                  onPressed: _loading ? null : _submit
                , style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14))
                , child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('로그인', style: TextStyle(fontSize: 16))
                )
              ]
            )
          )
        )
      )
    );
  }
}
