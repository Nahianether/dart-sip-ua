import 'package:flutter/material.dart';
// import 'package:flutter_bloc/flutter_bloc.dart'; // Removed - BLoC dependency removed
// import 'package:get_it/get_it.dart'; // Removed - GetIt dependency removed

// Clean Architecture Imports - Commented out due to removed dependencies
// import '../domain/usecases/make_call_usecase.dart';
// import '../domain/usecases/manage_call_usecase.dart';
// import '../domain/usecases/manage_account_usecase.dart';
// import '../domain/repositories/sip_repository.dart';
// import '../domain/repositories/storage_repository.dart';
// import '../data/repositories/sip_repository_impl.dart';
// import '../data/repositories/storage_repository_impl.dart';
// import '../data/datasources/sip_datasource.dart';
// import '../data/datasources/local_storage_datasource.dart';

// final GetIt getIt = GetIt.instance; // Removed - GetIt dependency removed

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Setup dependency injection - commented out due to removed dependencies
  // await setupDependencies();
  
  // Initialize background call service - commented out due to removed dependencies
  // await BackgroundCallService.initialize();
  
  runApp(AndroidSipApp());
}

Future<void> setupDependencies() async {
  // All dependency injection commented out due to removed BLoC and GetIt dependencies
  
  // Data sources
  // getIt.registerLazySingleton<LocalStorageDataSource>(() => SharedPreferencesDataSource());
  // getIt.registerLazySingleton<SipDataSource>(() => SipUADataSource());
  
  // Repositories
  // getIt.registerLazySingleton<StorageRepository>(() => StorageRepositoryImpl(getIt()));
  // getIt.registerLazySingleton<SipRepository>(() => SipRepositoryImpl(getIt()));
  
  // Use cases
  // getIt.registerLazySingleton<ManageAccountUsecase>(() => ManageAccountUsecase(getIt(), getIt()));
  // getIt.registerLazySingleton<MakeCallUsecase>(() => MakeCallUsecase(getIt()));
  // getIt.registerLazySingleton<ManageCallUsecase>(() => ManageCallUsecase(getIt(), getIt()));
  
  // Controllers (removed - BLoC no longer used)
  // getIt.registerFactory<AccountBloc>(() => AccountBloc(getIt()));
  // getIt.registerFactory<CallBloc>(() => CallBloc(getIt(), getIt()));
  
  // Initialize SIP data source
  // await getIt<SipDataSource>().initialize();
}

class AndroidSipApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Android SIP Client',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: Text('Legacy BLoC App - Use main.dart instead'),
        ),
      ), // MultiBlocProvider removed - use Riverpod main.dart instead
    );
  }
}

/*
// AppNavigator class commented out - BLoC no longer used
class AppNavigator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AccountBloc, AccountState>(
      builder: (context, state) {
        if (state is AccountLoading) {
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        if (state is AccountLoggedIn) {
          return BlocListener<CallBloc, CallState>(
            listener: (context, callState) {
              if (callState is CallIncoming) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CallScreen(call: callState.call),
                  ),
                );
              }
            },
            child: DialerScreen(),
          );
        }
        
        return LoginScreen();
      },
    );
  }
}
*/