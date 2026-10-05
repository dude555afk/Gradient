import '../models/model_router.dart';
import '../skills/skill_router.dart';

class TaskRoute {
  const TaskRoute({
    required this.model,
    required this.skills,
  });

  final ModelRole model;
  final List<SkillDefinition> skills;
}

class TaskRouter {
  const TaskRouter({
    this.modelRouter = const ModelRouter(),
    this.skillRouter = const SkillRouter(),
  });

  final ModelRouter modelRouter;
  final SkillRouter skillRouter;

  TaskRoute route(
    String task, {
    bool hasImages = false,
  }) {
    return TaskRoute(
      model: hasImages ? ModelRole.vision : modelRouter.select(task),
      skills: skillRouter.select(task),
    );
  }
}
