// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
	site: 'https://caseo-docs.lanzaderos.workers.dev',
	integrations: [
		starlight({
			title: 'Caseo',
			description: 'Guía para instalar Caseo en tu propio servidor.',
			locales: { root: { label: 'Español', lang: 'es' } },
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/lanzaderos/caseo' }],
			editLink: { baseUrl: 'https://github.com/lanzaderos/caseo/edit/main/docs/' },
			sidebar: [
				{
					label: 'Self-hosted',
					items: [
						{ slug: 'requisitos' },
						{ slug: 'instalacion' },
						{ slug: 'https' },
						{ slug: 'whatsapp' },
						{ slug: 'actualizaciones' },
						{ slug: 'copias-de-seguridad' },
					],
				},
			],
		}),
	],
});
