import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/di/app_dependencies.dart';
import '../../../../core/models/peer_identity.dart';
import '../../../../core/services/onboarding_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../../../home/presentation/pages/home_page.dart';

/// Onboarding screen that explains permissions and sets up P2P on first launch.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  static const routeName = '/onboarding';

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  final Logger _logger = const Logger('OnboardingPage');
  final _formKey = GlobalKey<FormState>();

  int _currentPage = 0;
  bool _isSettingUp = false;
  bool _setupComplete = false;
  String _setupStatus = '';

  // Profile setup state
  bool _showProfileSetup = false;
  bool _isSavingProfile = false;
  final _displayNameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _groupNameController = TextEditingController();
  UserRole _selectedRole = UserRole.student;

  @override
  void dispose() {
    _pageController.dispose();
    _displayNameController.dispose();
    _fullNameController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_checkExistingSetup);
  }

  Future<void> _setupP2p() async {
    setState(() {
      _isSettingUp = true;
      _setupStatus = 'Setting up permissions...';
    });

    try {
      final p2pService = AppDependencies.instance.p2pService;

      // Request permissions
      setState(() => _setupStatus = 'Requesting permissions...');
      try {
        await p2pService.checkAndRequestPermissions().timeout(
          const Duration(seconds: 30),
        );
      } on TimeoutException {
        _logger.info('Permission request timed out, continuing setup');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Enable services
      setState(() => _setupStatus = 'Enabling services...');
      await p2pService.checkAndEnableServices();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Check if everything is ready
      final permissionsGranted = await p2pService.areAllPermissionsGranted();
      final servicesEnabled = await p2pService.areAllServicesEnabled();

      if (permissionsGranted && servicesEnabled) {
        setState(() {
          _setupStatus = 'Setup complete!';
          _setupComplete = true;
        });
        _logger.info('P2P setup completed successfully');
        await _completeOnboarding();
        return;
      } else {
        setState(() {
          _setupStatus =
              'Setup incomplete. You can configure this later in Settings.';
          _setupComplete = true;
        });
        _logger.info('P2P setup incomplete');
      }
    } catch (e) {
      _logger.error('Error during P2P setup: $e');
      setState(() {
        _setupStatus =
            'Setup encountered an error. You can try again in Settings.';
        _setupComplete = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isSettingUp = false);
      }
    }
  }

  Future<void> _checkExistingSetup() async {
    final p2pService = AppDependencies.instance.p2pService;
    final permissionsGranted = await p2pService.areAllPermissionsGranted(
      requestIfMissing: false,
    );
    final servicesEnabled = await p2pService.areAllServicesEnabled();

    if (!mounted || !(permissionsGranted && servicesEnabled)) {
      return;
    }

    setState(() {
      _setupComplete = true;
      _setupStatus = 'Setup complete!';
    });

    await _completeOnboarding();
  }

  Future<void> _completeOnboarding() async {
    await OnboardingService().completeOnboarding();
    if (mounted) {
      // Show profile setup prompt
      setState(() => _showProfileSetup = true);
    }
  }

  Future<void> _skipProfileSetup() async {
    if (mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(HomePage.routeName, (route) => false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSavingProfile = true);

    final identityService = AppDependencies.instance.peerIdentityService;

    try {
      // Set display name first
      await identityService.setDisplayName(_displayNameController.text.trim());

      // Then update other profile fields
      await identityService.updateProfile(
        name: _fullNameController.text.trim().isEmpty
            ? null
            : _fullNameController.text.trim(),
        groupName: _groupNameController.text.trim().isEmpty
            ? null
            : _groupNameController.text.trim(),
        role: _selectedRole,
      );

      // Update app dependencies with new identity
      await AppDependencies.instance.updatePeerDisplayName(
        _displayNameController.text.trim(),
      );

      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(HomePage.routeName, (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showProfileSetup) {
      return _buildProfileSetupScreen();
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildWelcomePage(),
                  _buildPermissionsExplanationPage(),
                  _buildSetupPage(),
                ],
              ),
            ),
            _buildPageIndicator(),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSetupScreen() {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(
                Icons.person_add,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Set Up Your Profile?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Create a profile so others can identify you in chats. You can always do this later.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _buildProfileForm(),
              const SizedBox(height: 24),
              _buildProfilePreview(),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _isSavingProfile ? null : _saveProfile,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _isSavingProfile
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Profile'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _skipProfileSetup,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Skip for Now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Display Name',
              hintText: 'How you want to appear in chats',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Display name is required';
              }
              return null;
            },
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _fullNameController,
            decoration: const InputDecoration(
              labelText: 'Full Name (Optional)',
              hintText: 'Your real name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _groupNameController,
            decoration: const InputDecoration(
              labelText: 'Group/Class Name (Optional)',
              hintText: 'e.g., Class 10-A, Team Alpha',
              prefixIcon: Icon(Icons.group_outlined),
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<UserRole>(
            initialValue: _selectedRole,
            decoration: const InputDecoration(
              labelText: 'Role',
              prefixIcon: Icon(Icons.work_outline),
              border: OutlineInputBorder(),
            ),
            items: UserRole.values.map((role) {
              return DropdownMenuItem(
                value: role,
                child: Text(role.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedRole = value);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePreview() {
    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preview',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ProfileAvatar(
                  identity: PeerIdentity(
                    id: 'preview',
                    displayName: displayName,
                    name: _fullNameController.text.trim().isEmpty
                        ? null
                        : _fullNameController.text.trim(),
                    groupName: _groupNameController.text.trim().isEmpty
                        ? null
                        : _groupNameController.text.trim(),
                    role: _selectedRole,
                  ),
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (_fullNameController.text.trim().isNotEmpty)
                        Text(
                          _fullNameController.text.trim(),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _selectedRole.displayName,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                            ),
                          ),
                          if (_groupNameController.text.trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              _groupNameController.text.trim(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 120,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 32),
          Text(
            'Welcome to UsaApp',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Connect and chat with nearby devices without internet using peer-to-peer technology.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsExplanationPage() {
    final permissions = [
      _PermissionInfo(
        icon: Icons.location_on,
        title: 'Location & Nearby Devices',
        description:
            'Needed on Android to scan for nearby peers over Wi-Fi Direct and Bluetooth.',
      ),
      _PermissionInfo(
        icon: Icons.bluetooth,
        title: 'Bluetooth Access',
        description:
            'Required to advertise your device and maintain peer connections.',
      ),
      _PermissionInfo(
        icon: Icons.sd_storage,
        title: 'Media & Storage',
        description:
            'Allows sharing chats, media, and files with nearby devices.',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Permissions Needed',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'UsaApp needs these permissions to work:',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ...permissions.map(
            (permission) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    permission.icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          permission.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          permission.description,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupPage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isSettingUp)
            const CircularProgressIndicator()
          else if (_setupComplete)
            const Icon(Icons.check_circle, size: 80, color: Colors.green)
          else
            Icon(
              Icons.settings_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
          const SizedBox(height: 32),
          Text(
            _setupComplete ? 'Ready to Go!' : 'Setup P2P Connection',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            _setupStatus.isEmpty
                ? 'Tap the button below to configure permissions and services. This will allow UsaApp to discover and connect to nearby devices.'
                : _setupStatus,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          if (!_setupComplete && !_isSettingUp) ...[
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _setupP2p,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Setup'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          3,
          (index) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _currentPage == index
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade300,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentPage > 0)
            TextButton(
              onPressed: () {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: const Text('Back'),
            )
          else
            const SizedBox(width: 80),
          if (_currentPage < 2)
            ElevatedButton(
              onPressed: () {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: const Text('Next'),
            )
          else
            ElevatedButton(
              onPressed: _setupComplete && !_isSettingUp
                  ? _completeOnboarding
                  : null,
              child: const Text('Get Started'),
            ),
        ],
      ),
    );
  }
}

class _PermissionInfo {
  final IconData icon;
  final String title;
  final String description;

  _PermissionInfo({
    required this.icon,
    required this.title,
    required this.description,
  });
}
