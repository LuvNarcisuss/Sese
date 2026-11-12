alter table public.profiles
  drop constraint profiles_avatar_check,
  add constraint profiles_avatar_check
    check (avatar in ('expo-duo', 'fan-duo', 'expo-judy', 'expo-nick'));
