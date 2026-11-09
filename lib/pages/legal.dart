/* MANGACA legal — Privacy Policy, Terms of Service, Community Guidelines.
   Same standard wording as the web app, adjusted where the surface differs
   (the app stores its sign-in session on-device instead of a browser cookie).
   Zero internal-mechanism disclosure. */

import 'package:flutter/material.dart';
import '../widgets.dart';

class LegalDoc {
  final String title, updated;
  final List<(String, String)> body;
  const LegalDoc(this.title, this.updated, this.body);
}

const legalDocs = <String, LegalDoc>{
  'privacy': LegalDoc('PRIVACY POLICY', 'Last updated: November 9, 2026', [
    ('1. Who we are', 'MANGACA is a reading and streaming platform for manga, novels, classics, series and films. You manage your identity through the genjutsu passwordless identity system operated within the Orubus ecosystem, and you reach us any time through the @orubus_bot assistant on Telegram.'),
    ('2. What we collect', 'When you create an account we store the username and role you choose, the identifier of the verified identity you signed in with, and basic account timestamps. As you use the app we store your library, reading progress, reading history, likes, favorites and comments so these work across your devices. For security we keep a one-way hash of your device fingerprint and approximate network signals to detect mass account creation and abuse; these cannot be reversed into information about your device or identity.'),
    ('3. On-device session and storage', 'The app keeps one sign-in session token on your device; without it you cannot stay signed in, so it cannot be switched off. We also keep your preferences (theme, reader mode, player settings) and your library, progress and history on the device, and — while you are signed in — sync progress and library to your account. We do not run third-party advertising or cross-site tracking.'),
    ('4. How your data is used', 'Your data is used only to operate your account and the service: remembering where you stopped reading, showing your library and history, counting likes and displaying comments, protecting accounts against abuse, and communicating service messages. We do not sell personal data, and we do not share it with data brokers.'),
    ('5. Content partners', 'Series and films are delivered with the help of independent content delivery partners. When you press play, the video stream is delivered to your device by the partner serving that title, over your own connection. We do not sell your identity to these partners and we do not pass your account details to them as part of playback.'),
    ('6. Retention', 'Account and library data are kept while your account exists. Comments you post are visible to others until you or we remove them. Security records are kept for a limited period and then deleted. Signing out revokes the session on the device that asked; deleting an account removes its data.'),
    ('7. Your choices', 'You can sign out from any device, clear the app’s on-device data, and contact us through @orubus_bot to request access to, correction of, or deletion of your account data. We respond to every good-faith request.'),
    ('8. Children', 'MANGACA is not directed at children under the digital-consent age in your country. If you believe a child has created an account, contact us and we will remove it.'),
    ('9. Changes', 'If this policy changes in a way that matters, the app will tell you — through a notice in the app or through the bot — before the change takes effect.'),
  ]),
  'terms': LegalDoc('TERMS OF SERVICE', 'Last updated: November 9, 2026', [
    ('1. Agreement', 'By creating an account or using MANGACA you agree to these terms. If you do not agree, do not use the service. These terms apply to the website, this app, and any other surface carrying the MANGACA name.'),
    ('2. Accounts', 'Accounts are created through the passwordless genjutsu identity flow: you verify an identity you control, then choose a username and a role (reader, author or publisher). One person keeps one account; usernames are unique across the whole platform and are protected by the same systems that protect the rest of the service. You are responsible for the devices you stay signed in on, and you can sign any device out at any time.'),
    ('3. Acceptable use', 'Do not attack, overload or interfere with the service; do not automate access in ways that degrade it for others; do not attempt to circumvent sign-in, security checks or usage limits; do not re-publish or resell the catalog or streams; do not use the service where doing so would break the law that applies to you.'),
    ('4. Authors and publishers', 'If you publish under an author or publisher role you confirm you hold the rights you need for everything you upload, that it is correctly labelled, and that it does not contain unlawful material, malware, or content that sexualises minors. We may remove material and suspend publishing privileges when a credible complaint arrives.'),
    ('5. Community', 'Comments, likes and library features are provided in good faith. Harassment, hate speech, spam, scams and impersonation are not allowed. The Community Guidelines are part of these terms.'),
    ('6. Content and availability', 'Original MANGACA titles belong to their creators. Catalog availability, streaming quality and playback partners can change without notice; we do not promise that any specific title stays available. Video is delivered in part by independent delivery partners; their availability is outside our control.'),
    ('7. Disclaimers', 'The service is provided “as is” and “as available”. To the fullest extent the law allows, MANGACA disclaims warranties of merchantability, fitness for a particular purpose and non-infringement, and does not warrant uninterrupted or error-free operation.'),
    ('8. Liability', 'To the fullest extent the law allows, MANGACA and its operators are not liable for indirect, incidental, special or consequential damages, or for loss of data, profits or goodwill arising from your use of the service.'),
    ('9. Suspension and termination', 'We may suspend or end accounts that break these terms, abuse the platform, or create risk for other users. You may stop using the service at any time and request deletion of your account data through @orubus_bot.'),
    ('10. Changes and governing law', 'We may update these terms; material updates are announced in the app. Continued use after an update means acceptance. These terms are governed by the laws of the Federal Republic of Nigeria, without prejudice to mandatory consumer protections in your country of residence.'),
  ]),
  'guidelines': LegalDoc('COMMUNITY GUIDELINES', 'Last updated: November 9, 2026', [
    ('The short version', 'Be decent. Talk about stories, not about people. Mark your spoilers. Do not spam, scam, harass or impersonate. Upload only what you have the right to publish. Break the rules and your comments, uploads or account can be removed.'),
    ('1. Treat people well', 'Critique stories as hard as you like; attack people never. No harassment, doxxing, hate speech, threats or targeted mockery. Debates get heated — keep them about the story.'),
    ('2. Mark your spoilers', 'Nothing kills a first watch or first read like an unmarked ending. Label spoilers in comments, and keep explicit material out of titles, usernames and public fields.'),
    ('3. No spam, scams or manipulation', 'No bulk posting, referral spam, phishing links, fake giveaways, pyramid schemes or engagement farming. Do not like-farm or mass-create accounts; abuse detection applies.'),
    ('4. Upload what is yours', 'Authors and publishers must hold the rights to what they publish and keep uploads correctly labelled. Counterfeit uploads, ripped paid content and malware-bearing files are removed on sight, and repeat offenders lose publishing privileges.'),
    ('5. Keep it lawful', 'No content or conduct that is illegal under the laws that apply to you or to the platform, including CSAM, terror recruitment, targeted incitement and the sale of regulated goods.'),
    ('6. Enforcement', 'Most problems are handled with a warning and a removal. Serious or repeated violations lead to losing the relevant role, suspension, or a permanent ban. We keep enforcement proportionate and record what was done.'),
    ('7. Reporting', 'Report problems through @orubus_bot with links and, where relevant, screenshots. Reports about copyright are actioned when they identify the specific work and the claimed right.'),
  ]),
};

class LegalPage extends StatelessWidget {
  final String kind;
  const LegalPage({super.key, required this.kind});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final doc = legalDocs[kind];
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        foregroundColor: p.fg,
        elevation: 0,
        title: Text(doc?.title ?? 'LEGAL', style: tDisplay(12).copyWith(color: p.fg, letterSpacing: 1.4)),
      ),
      body: doc == null
          ? Center(child: Text('Not found.', style: tUi(12.5).copyWith(color: p.dim)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
              children: [
                Text(doc.updated, style: tUi(10.5).copyWith(color: p.faint)),
                const SizedBox(height: 6),
                for (final (h, text) in doc.body) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.bg2,
                      border: Border.all(color: p.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h, style: tDisplay(11.5).copyWith(color: p.fg, letterSpacing: 1.2)),
                        const SizedBox(height: 6),
                        Text(text, style: tUi(12).copyWith(color: p.fg.withOpacity(0.92), height: 1.65)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text('Questions? Reach us any time through @orubus_bot on Telegram.',
                    style: tUi(11).copyWith(color: p.faint)),
              ],
            ),
    );
  }
}
