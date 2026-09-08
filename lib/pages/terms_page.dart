import 'package:flutter/material.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/terms/agree_button.dart';
import 'package:quark/widgets/terms/terms_section.dart';

/// Terms and Conditions acceptance gate.
///
/// Shown on first launch (or after a reset) before the user can access the app.
/// Tapping "I Agree" persists the acceptance via [AppSettings] and navigates
/// straight to wherever the user belongs next — setup, login, or the file
/// browser.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Terms and Conditions',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Last updated: September 8, 2026',
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: 24),
                  TermsSection(
                    title: 'Definitions',
                    body:
                        'AutoButler (or AutoButler LLC, "we", "us", "our") '
                        'means the company that owns and sells Quark and '
                        'operates autobutler.org.\n\n'
                        'Quark means the personal cloud hardware product and '
                        'related software experience sold or distributed by '
                        'AutoButler.\n\n'
                        'Software means the Quark application and related '
                        'open-source components that run on your Quark device '
                        '(or other supported hardware you control). The '
                        'Software is not "the AutoButler application."\n\n'
                        'Website means autobutler.org and related '
                        'AutoButler-operated web properties (including '
                        'waitlist and marketing pages).',
                  ),
                  TermsSection(
                    title: '1. Personal Use',
                    body:
                        'Quark is designed for personal use to manage and '
                        'back up your own photos and files. You may not use '
                        'the Software to store or distribute content that '
                        'violates applicable laws or the rights of others.',
                  ),
                  TermsSection(
                    title: '2. Your Data',
                    body:
                        'You retain full ownership of all data you store with '
                        'Quark. By default your content stays on hardware you '
                        'control. Any optional backup or sync service we may '
                        'offer later would require your explicit opt-in.\n\n'
                        'Some features (for example remote access via a '
                        'mesh/VPN you enable, or optional imports from '
                        'third-party services you choose) may involve '
                        'third-party networks or services. Those paths happen '
                        'only when you set them up or take an explicit '
                        'action. You are solely responsible for the security '
                        'and backup of your data and for any third-party '
                        'services you connect.',
                  ),
                  TermsSection(
                    title: '3. No Warranty',
                    body:
                        'Quark and the Software are provided "as is", without '
                        'warranty of any kind, express or implied. We make no '
                        'guarantees regarding uptime, data integrity, or '
                        'fitness for a particular purpose. Use at your own '
                        'risk.\n\n'
                        'Hardware purchase warranties, if any, will be stated '
                        'separately at the point of sale or in the applicable '
                        'product materials.',
                  ),
                  TermsSection(
                    title: '4. Acceptable Use',
                    body:
                        'You agree not to use Quark for any unlawful purpose, '
                        'to attempt to gain unauthorised access to other '
                        'systems, or to interfere with the operation of the '
                        'Software for other users. Because Quark primarily '
                        'runs on hardware you control and we generally have '
                        'no access to your device content, these terms are '
                        'legally binding but often not technically '
                        'enforceable by us against on-device activity. You '
                        'are solely responsible for your own compliance with '
                        'applicable laws.',
                  ),
                  TermsSection(
                    title: '5. Limitation of Liability',
                    body:
                        'To the maximum extent permitted by law, AutoButler '
                        'and the developers of Quark shall not be liable for '
                        'any indirect, incidental, special, or consequential '
                        'damages arising from your use of Quark, the Software, '
                        'or the Website, even if advised of the possibility '
                        'of such damages.',
                  ),
                  TermsSection(
                    title: '6. Website / Waitlist',
                    body:
                        'If you join a waitlist, create an account on the '
                        'Website, or contact us, you agree to provide '
                        'accurate information and to receive operational '
                        'messages related to that request (for example '
                        'waitlist confirmation or support replies). Marketing '
                        'emails, if any, will follow applicable consent and '
                        'unsubscribe rules.',
                  ),
                  TermsSection(
                    title: '7. Changes to These Terms',
                    body:
                        'We may update these Terms from time to time. For '
                        'material changes, we will post an updated version on '
                        'the Website (and in-app where applicable) with a '
                        'revised "Last updated" date. Continued use of Quark '
                        'or the Website after changes are posted constitutes '
                        'acceptance of the revised Terms, except where '
                        'applicable law requires a different process.',
                  ),
                  TermsSection(
                    title: '8. Contact',
                    body:
                        'Questions about these Terms: '
                        'support@autobutler.org. Software license details for '
                        'open-source components: '
                        'https://github.com/autobutler-org/quark',
                  ),
                ],
              ),
            ),
          ),
          const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: SizedBox(width: double.infinity, child: AgreeButton()),
            ),
          ),
        ],
      ),
    );
  }
}
